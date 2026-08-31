#!/usr/bin/env python3
"""Package a directory into /root of a gzipped newc cpio rootfs.

This script is intentionally self-contained: it does not shell out to cpio.
It copies the provided bzImage unchanged and writes a new rootfs.cpio.gz with
the payload directory merged into the target directory inside the archive.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import shutil
import stat
import sys
import time
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


HEADER_LEN = 110
TRAILER = "TRAILER!!!"


@dataclass
class Entry:
    name: str
    fields: dict[str, int]
    data: bytes


def align4(value: int) -> int:
    return (value + 3) & ~3


def pad4(value: int) -> int:
    return align4(value) - value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_archive_name(name: str) -> str:
    while name.startswith("./"):
        name = name[2:]
    return name


def parse_newc(blob: bytes) -> list[Entry]:
    entries: list[Entry] = []
    pos = 0

    while True:
        header = blob[pos : pos + HEADER_LEN]
        if len(header) != HEADER_LEN:
            raise ValueError(f"truncated cpio header at offset {pos}")
        pos += HEADER_LEN

        magic = header[:6].decode("ascii")
        if magic not in {"070701", "070702"}:
            raise ValueError(f"unsupported cpio magic {magic!r} at offset {pos - HEADER_LEN}")

        values = [int(header[i : i + 8], 16) for i in range(6, HEADER_LEN, 8)]
        namesize = values[11]
        filesize = values[6]

        name_raw = blob[pos : pos + namesize]
        if len(name_raw) != namesize:
            raise ValueError(f"truncated cpio name at offset {pos}")
        pos += namesize
        pos += pad4(HEADER_LEN + namesize)

        name = name_raw[:-1].decode("utf-8", "surrogateescape")
        data = blob[pos : pos + filesize]
        if len(data) != filesize:
            raise ValueError(f"truncated cpio data for {name}")
        pos += filesize
        pos += pad4(filesize)

        fields = {
            "ino": values[0],
            "mode": values[1],
            "uid": values[2],
            "gid": values[3],
            "nlink": values[4],
            "mtime": values[5],
            "devmajor": values[7],
            "devminor": values[8],
            "rdevmajor": values[9],
            "rdevminor": values[10],
            "check": values[12],
        }

        if name == TRAILER:
            break
        entries.append(Entry(normalize_archive_name(name), fields, data))

    return entries


def make_header(name: str, fields: dict[str, int], filesize: int) -> bytes:
    name_size = len(name.encode("utf-8", "surrogateescape")) + 1
    values = [
        fields.get("ino", 0),
        fields["mode"],
        fields.get("uid", 0),
        fields.get("gid", 0),
        fields.get("nlink", 1),
        fields.get("mtime", 0),
        filesize,
        fields.get("devmajor", 0),
        fields.get("devminor", 0),
        fields.get("rdevmajor", 0),
        fields.get("rdevminor", 0),
        name_size,
        fields.get("check", 0),
    ]
    return ("070701" + "".join(f"{value & 0xFFFFFFFF:08x}" for value in values)).encode("ascii")


def write_entry(handle, entry: Entry) -> None:
    name_bytes = entry.name.encode("utf-8", "surrogateescape") + b"\0"
    handle.write(make_header(entry.name, entry.fields, len(entry.data)))
    handle.write(name_bytes)
    handle.write(b"\0" * pad4(HEADER_LEN + len(name_bytes)))
    handle.write(entry.data)
    handle.write(b"\0" * pad4(len(entry.data)))


def write_newc_gzip(entries: list[Entry], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with gzip.GzipFile(filename=str(output), mode="wb", compresslevel=9, mtime=0) as gz:
        for entry in entries:
            write_entry(gz, entry)
        write_entry(
            gz,
            Entry(
                TRAILER,
                {
                    "ino": 0,
                    "mode": 0,
                    "uid": 0,
                    "gid": 0,
                    "nlink": 1,
                    "mtime": 0,
                    "devmajor": 0,
                    "devminor": 0,
                    "rdevmajor": 0,
                    "rdevminor": 0,
                    "check": 0,
                },
                b"",
            ),
        )


def clean_archive_dir(value: str) -> str:
    normalized = str(PurePosixPath(value.replace("\\", "/")))
    normalized = normalized.lstrip("/")
    normalized = normalize_archive_name(normalized).rstrip("/")
    if not normalized or normalized == ".":
        raise argparse.ArgumentTypeError("archive destination must not be empty or /")
    if any(part in {"", ".", ".."} for part in normalized.split("/")):
        raise argparse.ArgumentTypeError("archive destination must not contain empty, . or .. parts")
    return normalized


def payload_file_mode(path: Path, payload_dir: Path, executable_policy: str) -> int:
    if path.is_dir():
        return stat.S_IFDIR | 0o755
    if executable_policy == "all":
        executable = True
    elif executable_policy == "none":
        executable = False
    else:
        # PolyLinux ships extensionless shell helpers. Their executable bits
        # are not reliable in Windows checkouts, so apply the canonical modes
        # explicitly while packaging.
        executable = path.suffix == ".sh" or path.name in {
            "nextlevel",
            "prevlevel",
            "process-helper",
            "profile",
            "startlevel",
        }
    return stat.S_IFREG | (0o755 if executable else 0o644)


def normalize_payload_text(data: bytes) -> bytes:
    """Convert Windows CRLF to Unix LF without modifying binary payloads."""
    if b"\x00" in data:
        return data
    return data.replace(b"\r\n", b"\n")


def build_payload_entries(
    payload_dir: Path,
    archive_dest: str,
    start_ino: int,
    executable_policy: str,
) -> list[Entry]:
    entries: list[Entry] = []
    ino = start_ino
    now = int(time.time())
    dirs: set[str] = set()

    current = PurePosixPath(archive_dest)
    archive_dest_parts = current.parts
    for idx in range(1, len(archive_dest_parts) + 1):
        dirs.add(PurePosixPath(*archive_dest_parts[:idx]).as_posix())

    payload_paths = sorted(
        path for path in payload_dir.rglob("*")
        if ".git" not in path.relative_to(payload_dir).parts
    )

    for path in payload_paths:
        rel = path.relative_to(payload_dir).as_posix()
        archive_name = f"{archive_dest}/{rel}"
        parent = PurePosixPath(archive_name).parent.as_posix()
        while parent and parent not in {".", archive_dest}:
            dirs.add(parent)
            parent = PurePosixPath(parent).parent.as_posix()
        if path.is_dir():
            dirs.add(archive_name)

    for dirname in sorted(dirs):
        ino += 1
        entries.append(
            Entry(
                dirname,
                {
                    "ino": ino,
                    "mode": stat.S_IFDIR | 0o755,
                    "uid": 0,
                    "gid": 0,
                    "nlink": 2,
                    "mtime": now,
                    "devmajor": 0,
                    "devminor": 0,
                    "rdevmajor": 0,
                    "rdevminor": 0,
                    "check": 0,
                },
                b"",
            )
        )

    for path in (item for item in payload_paths if item.is_file()):
        rel = path.relative_to(payload_dir).as_posix()
        payload_data = normalize_payload_text(path.read_bytes())
        ino += 1
        entries.append(
            Entry(
                f"{archive_dest}/{rel}",
                {
                    "ino": ino,
                    "mode": payload_file_mode(path, payload_dir, executable_policy),
                    "uid": 0,
                    "gid": 0,
                    "nlink": 1,
                    "mtime": int(path.stat().st_mtime),
                    "devmajor": 0,
                    "devminor": 0,
                    "rdevmajor": 0,
                    "rdevminor": 0,
                    "check": 0,
                },
                payload_data,
            )
        )

    return entries


def merge_entries(original: list[Entry], payload: list[Entry]) -> list[Entry]:
    payload_names = {entry.name for entry in payload}
    merged: list[Entry] = []
    seen: set[str] = set()

    for entry in original:
        name = normalize_archive_name(entry.name)
        if name in payload_names:
            continue
        entry.name = name
        merged.append(entry)
        seen.add(name)

    for entry in payload:
        if entry.name not in seen:
            merged.append(entry)
    return merged


def write_manifest(
    manifest_dir: Path,
    source_bzimage: Path,
    source_rootfs: Path,
    output_bzimage: Path,
    output_rootfs: Path,
    payload_entries: list[Entry],
    archive_dest: str,
) -> None:
    manifest_dir.mkdir(parents=True, exist_ok=True)
    (manifest_dir / "payload-files.txt").write_text(
        "\n".join(
            f"{stat.filemode(entry.fields['mode'])} {entry.fields['uid']}:{entry.fields['gid']} {entry.name}"
            for entry in payload_entries
        )
        + "\n",
        encoding="utf-8",
    )
    (manifest_dir / "artifact-sha256.txt").write_text(
        "\n".join(
            [
                f"source-bzImage  {sha256_file(source_bzimage)}",
                f"source-rootfs  {sha256_file(source_rootfs)}",
                f"output-bzImage  {sha256_file(output_bzimage)}",
                f"output-rootfs  {sha256_file(output_rootfs)}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (manifest_dir / "validation-notes.md").write_text(
        "\n".join(
            [
                "# Validation Notes",
                "",
                f"- Payload directory merged into `{archive_dest}/`.",
                "- Existing archive entries with the same paths were replaced.",
                "- bzImage was copied unchanged.",
                "- Boot validation was not run by this script.",
            ]
        )
        + "\n",
        encoding="utf-8",
    )


def package_rootfs(args: argparse.Namespace) -> None:
    bzimage = args.bzimage.resolve()
    rootfs = args.rootfs.resolve()
    payload_dir = args.payload_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_bzimage = output_dir / args.output_bzimage_name
    output_rootfs = output_dir / args.output_rootfs_name
    manifest_dir = output_dir / args.manifest_dir_name

    if not bzimage.is_file():
        raise FileNotFoundError(f"bzImage not found: {bzimage}")
    if not rootfs.is_file():
        raise FileNotFoundError(f"rootfs not found: {rootfs}")
    if not payload_dir.is_dir():
        raise FileNotFoundError(f"payload directory not found: {payload_dir}")
    if not any(payload_dir.iterdir()):
        raise ValueError(f"payload directory is empty: {payload_dir}")

    output_dir.mkdir(parents=True, exist_ok=True)
    if not args.force:
        existing = [path for path in (output_bzimage, output_rootfs) if path.exists()]
        if existing:
            names = ", ".join(str(path) for path in existing)
            raise FileExistsError(f"output already exists; use --force to overwrite: {names}")

    source_bz_hash = sha256_file(bzimage)
    source_rootfs_hash = sha256_file(rootfs)

    with gzip.open(rootfs, "rb") as gz:
        original_entries = parse_newc(gz.read())
    max_ino = max((entry.fields.get("ino", 0) for entry in original_entries), default=0)
    payload_entries = build_payload_entries(payload_dir, args.archive_dest, max_ino, args.executable_policy)
    merged_entries = merge_entries(original_entries, payload_entries)

    shutil.copyfile(bzimage, output_bzimage)
    write_newc_gzip(merged_entries, output_rootfs)

    if sha256_file(bzimage) != source_bz_hash:
        raise RuntimeError("source bzImage changed during packaging")
    if sha256_file(rootfs) != source_rootfs_hash:
        raise RuntimeError("source rootfs changed during packaging")
    if sha256_file(output_bzimage) != source_bz_hash:
        raise RuntimeError("output bzImage does not match source bzImage")

    if args.manifest:
        write_manifest(
            manifest_dir,
            bzimage,
            rootfs,
            output_bzimage,
            output_rootfs,
            payload_entries,
            args.archive_dest,
        )

    print(f"Wrote {output_bzimage}")
    print(f"Wrote {output_rootfs}")
    if args.manifest:
        print(f"Wrote {manifest_dir}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Copy bzImage and merge a payload directory into a gzipped newc cpio rootfs.",
    )
    parser.add_argument("--bzimage", required=True, type=Path, help="Source bzImage to copy unchanged.")
    parser.add_argument("--rootfs", required=True, type=Path, help="Source rootfs.cpio.gz to modify.")
    parser.add_argument(
        "--payload-dir",
        required=True,
        type=Path,
        help="Directory whose contents are copied into the archive destination.",
    )
    parser.add_argument("--output-dir", required=True, type=Path, help="Directory for output images.")
    parser.add_argument("--output-bzimage-name", default="bzImage", help="Output kernel filename.")
    parser.add_argument("--output-rootfs-name", default="rootfs.cpio.gz", help="Output rootfs filename.")
    parser.add_argument(
        "--archive-dest",
        default="root",
        type=clean_archive_dir,
        help="Destination directory inside the rootfs archive, default: root.",
    )
    parser.add_argument(
        "--executable-policy",
        choices=("sh", "all", "none"),
        default="sh",
        help="Permissions for payload files: executable .sh files only, all files, or no files.",
    )
    parser.add_argument("--force", action="store_true", help="Overwrite existing output files.")
    parser.add_argument("--no-manifest", dest="manifest", action="store_false", help="Do not write manifest files.")
    parser.add_argument("--manifest-dir-name", default="manifest", help="Manifest directory name under output-dir.")
    parser.set_defaults(manifest=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        package_rootfs(args)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

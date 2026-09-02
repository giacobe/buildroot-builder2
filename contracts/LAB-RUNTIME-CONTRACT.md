# PolyLinux lab runtime contract

Every new or migrated lab payload must include the canonical
`polylinux-colors.sh` from this directory without modification. The installer
copies it to `/etc/profile.d/polylinux-colors.sh` with mode `0644`, and the learner
profile sources it before displaying instructions.

The palette is designed for the black v86 terminal and gives high-contrast colors
to directories, executables, symbolic links, archives, special files, and broken
links. GNU Coreutils `ls` must be invoked through `alias ls='ls --color=auto'` so
interactive listings are colored but pipelines and redirected output remain free
of ANSI escape sequences. Do not depend on BusyBox's implicit color default.

Release tests must verify that:

- the lab copy is byte-identical to the canonical file;
- the installer deploys the file and the learner profile sources it;
- representative interactive `ls` output contains the expected ANSI categories;
- `ls` redirected to a file or pipe contains no ANSI escape sequences;
- the exact packaged rootfs contains the canonical file; and
- the exact packaged image is visually checked in v86 before publication.

Level construction is bounded and parallel, normally with up to ten workers. Every
home is first published with a pending `README.txt`; successful builders replace it
only after all evidence is ready, and failed builders replace it with a build-log
notice. Navigation does not block on readiness and intentional skipping is allowed.

The client VM must not contain answer-key files, `checklevel`, or another local
correctness oracle. Learners submit answers through the external exercise grading
form. Deterministic expected values belong only in repository test fixtures and the
separate Microsoft Forms/Power Automate grading workflow, never in the packaged
payload.

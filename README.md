# sage-ctf-docker (SageMath 10.8 CTF toolchain)

This repository builds a reproducible Docker image for CTF crypto/reversing that is verified to work with SageMath 10.8.

## What’s inside

- Base: official Sage image `sagemath/sagemath:10.8` (Ubuntu-based), pinned by digest in `repro.lock`.
- Python 3.13 (primary): `uv` managed interpreter + venv at `/opt/venvs/py313`.
- Python 2.7 (fallback): isolated `micromamba` env, wrapper `/usr/local/bin/py27`.
- Sage 10.8: system `sage` CLI from the base image.
- Tools: `flatter` (LLL accelerator), `r2` (radare2, built from source), `tshark`, headless Java runtime.
- Repos vendored at build-time for availability: `crypto-attacks`, `gf2bv`, `or-tools` (cloned at pinned SHAs).

## Verified (smoke)

The image ships `/opt/verify/smoke.sh` which checks:

- `sage --version` is **10.8 stable**, and `sage -c 'print(2+2)'` works.
- Python 3.13 imports: `pwntools`, `paramiko`, `rpyc`, `unicorn`, `z3-solver`, `ortools`, `pycryptodome`, `cryptography`, `pynacl`, `zstandard`.
- `gf2bv` runs under Python 3.13 (only; see notes below).
- System tools present: `java`, `r2`, `tshark`, `flatter`.
- `crypto-attacks` unit tests pass under `sage -python` (85 tests).

## Paths & usage cheatsheet

- SageMath:
  - Binary: `/usr/bin/sage` (symlink to `/home/sage/sage/sage`)
  - Sage Python: `sage -python` (prints the Sage venv interpreter)
  - Example: `sage -c "print(2+2)"`
- Python 3.13 (uv venv):
  - Venv: `/opt/venvs/py313`
  - Python: `/opt/venvs/py313/bin/python`
  - Activate: `source /opt/venvs/py313/bin/activate`
- Python 2.7 (micromamba fallback):
  - Wrapper: `/usr/local/bin/py27`
  - Example: `py27 -c "import sys; print(sys.version)"`
- Installed tools:
  - `flatter`: `/usr/local/bin/flatter`
  - `r2` (radare2): `/usr/local/bin/r2`
  - `tshark`: `/usr/bin/tshark`
  - `java`: `/usr/bin/java`
- Sources cloned during build (pinned by `repro.lock`):
  - `/opt/src/crypto-attacks`
  - `/opt/src/gf2bv`
  - `/opt/src/flatter`
  - `/opt/src/or-tools`
  - `/opt/src/radare2`
- Verification script: `/opt/verify/smoke.sh`

## Notes / intentional exclusions

- `gf2bv` is installed into **Python 3.13 only**, not into Sage’s Python (stability-first; avoids native-extension crash risk).
- `pycryptosat` is **not installed into Sage’s Python** due to observed binary/ABI symbol mismatch in this environment.

## Build

Reproducible build (recommended):

```bash
bash repro-build.sh --update --base-image sagemath/sagemath:10.8 --dockerfile Dockerfile.official --tag sage-ctf:10.8
```

Then run smoke:

```bash
docker run --rm --entrypoint bash -t sage-ctf:10.8 -lc /opt/verify/smoke.sh
```

## Run (interactive)

```bash
docker run --rm -it sage-ctf:10.8 bash
```

## Dockerfile options

- `Dockerfile.official` (recommended): starts from `sagemath/sagemath:10.8`.
- `Dockerfile`: Debian 13 base + build Sage from source (very slow; may require extra tuning).

## Reproducibility

- `repro-build.sh` writes/uses `repro.lock` to pin:
  - base image digest
  - tool versions (`uv`, `micromamba`)
  - git SHAs for: Sage (tag 10.8), `flatter`, `radare2`, `gf2bv`, `crypto-attacks`, `or-tools`

Key build args (advanced):

- `ENABLE_SAGE` (default `1`)
- `SAGE_BRANCH` (default `master`)
- `SAGE_REPO` (default `https://github.com/sagemath/sage.git`)
- `SAGE_MAKEFLAGS` (default `-j$(nproc) -l$(nproc).5`)
- `SAGE_BUILD_STEP` (default `make`, options: `none`, `configure`, `make`)

## Remote build (via SSH)

Copy this folder to your remote host and build there:

```bash
scp -P <port> -r . root@<host>:/root/sage-ctf-docker
ssh -p <port> root@<host> 'cd /root/sage-ctf-docker && bash repro-build.sh --dockerfile Dockerfile.official --tag sage-ctf:10.8'
```

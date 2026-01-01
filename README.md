# Sage 10.8 + CTF Crypto Toolchain

This folder builds a reproducible Docker image that:

- Provides SageMath 10.8 (either via source build on Debian 13, or via the official Sage image).
- Builds and installs `flatter` (`https://github.com/keeganryan/flatter.git`) system-wide.
- Installs `gf2bv` (`https://github.com/maple3142/gf2bv.git`) into Python 3.13 (`uv` venv). (Not installed into Sage's Python to avoid native-extension segfault risk.)
- Clones `crypto-attacks` (`https://github.com/jvdsn/crypto-attacks.git`) and runs its unit tests using Sage.
- Provisions an isolated Python 2.7 fallback via `micromamba` (kept separate from `uv`).
- Installs common CTF crypto Python libraries into Sage + Python 3.13 (+ a legacy-compatible subset for Python 2.7).
- Clones `https://github.com/google/or-tools.git` for source availability and installs `ortools` into Python 3.13 (and attempts Sage).
- Installs common system tools for CTF reversing/networking: `r2` (radare2), `tshark`, and a headless Java runtime.

## Build

From this directory:

```bash
docker build -t debian13-sage-ctf .
```

## Dockerfile modes

- `Dockerfile`: Debian 13 base + build Sage from source (slow but Debian-native).
- `Dockerfile.official`: base on `sagemath/sagemath:10.8` (fast, but Ubuntu-based).

## Reproducible build (recommended)

Use the single script `docker/debian13-sage-ctf/repro-build.sh` to pin upstream git commits + tool versions into `docker/debian13-sage-ctf/repro.lock`, then build with those pins.

```bash
bash docker/debian13-sage-ctf/repro-build.sh --update --tag debian13-sage-ctf:repro
```

Fast (official Sage base):

```bash
bash docker/debian13-sage-ctf/repro-build.sh --update --base-image sagemath/sagemath:10.8 --dockerfile Dockerfile.official --tag sage-ctf:10.8
```

By default, Sage is pinned to `10.8` (to satisfy reproducibility + a fixed Sage major/minor). Override if needed:

```bash
bash docker/debian13-sage-ctf/repro-build.sh --update --sage-version 10.8 --tag debian13-sage-ctf:repro
```

Quick (skip Sage build):

```bash
bash docker/debian13-sage-ctf/repro-build.sh --update --quick --tag debian13-sage-ctf:quick
```

Key build args:

- `ENABLE_SAGE` (default `1`)
- `SAGE_BRANCH` (default `master`)
- `SAGE_REPO` (default `https://github.com/sagemath/sage.git`)
- `SAGE_MAKEFLAGS` (default `-j$(nproc) -l$(nproc).5`)
- `SAGE_BUILD_STEP` (default `make`, options: `none`, `configure`, `make`)

Example:

```bash
docker build -t debian13-sage-ctf --build-arg SAGE_BRANCH=master .
```

For a faster build that only validates Sage `./configure` (does not compile Sage):

```bash
docker build -t debian13-sage-ctf:configure --build-arg SAGE_BUILD_STEP=configure .
```

## Run

```bash
docker run --rm -it debian13-sage-ctf bash
```

## Verify (inside the container)

```bash
/opt/verify/smoke.sh
```

If dependency downloads occasionally time out during the build, increase `UV_HTTP_TIMEOUT` (default is set in the Dockerfiles; override by editing the Dockerfile `ENV` if needed).

## Remote build (via SSH)

Copy this folder to your remote host and build there:

```bash
scp -P <port> -r docker/debian13-sage-ctf root@<host>:/root/
ssh -p <port> root@<host> 'cd /root/debian13-sage-ctf && bash repro-build.sh --dockerfile Dockerfile.official --tag sage-ctf:10.8'
```

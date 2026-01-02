# sage-ctf-docker (SageMath 10.8 CTF toolchain)

This repository builds a reproducible Docker image for CTF crypto/reversing that is verified to work with SageMath 10.8.

## What’s inside

- Base: official Sage image `sagemath/sagemath:10.8` (Ubuntu-based), pinned by digest in `repro.lock`.
- Python 3.13 (primary): `uv` managed interpreter + venv at `/opt/venvs/py313`.
- Python 2.7 (fallback): isolated `micromamba` env at `/opt/micromamba/envs/py27` with shims (`python2`/`pip2`/`py27`).
- Sage 10.8: system `sage` CLI from the base image.
- Rust toolchain: `rustup` (official installer), pinned toolchain via `repro.lock`.
- JS tooling: Node.js + Bun (pinned, installed from official upstream release artifacts).
- Tools: `flatter` (LLL accelerator), `r2` (radare2, built from source), `tshark`, headless Java runtime, `jadx` (DEX decompiler, CLI).
- Repos vendored at build-time for availability: `crypto-attacks`, `gf2bv`, `or-tools` (cloned at pinned SHAs).

## Verified (smoke)

The image ships `/opt/verify/smoke.sh` which checks:

- `sage --version` is **10.8 stable**, and `sage -c 'print(2+2)'` works.
- Python 3.13 imports: `pwntools`, `paramiko`, `rpyc`, `unicorn`, `z3-solver`, `ortools`, `pycryptodome`, `cryptography`, `pynacl`, `zstandard`.
- `gf2bv` runs under Python 3.13 (only; see notes below).
- System tools present: `java`, `r2`, `tshark`, `flatter`.
- `crypto-attacks` unit tests pass under `sage --python` (85 tests).

## Paths & usage cheatsheet

容器内我们做了“命令别名/入口”分流：交互式 `bash` 默认把 `python/python3/pip/pip3` 指向 CTF 主 Python 3.13；同时用 `sage` 包装器保证 Sage 启动时仍然使用 Sage 自己的 `python3`，避免被 CTF 环境影响。

| 命令 | 真实入口/路径 | 指向/说明 |
|---|---|---|
| `sage` | `/usr/bin/sage` | SageMath 10.8（基于官方镜像） |
| `sage` (实际运行) | `/usr/local/bin/sage` | 包装器：运行前临时把 `PATH` 头部指向 `/home/sage/sage/local/bin`，确保 Sage 用自己的 `python3` |
| `sage --python` | (内部解析) | Sage 自带 venv 的 Python（当前为 3.12.x） |
| `sage --pip` | (内部解析) | Sage 自带 venv 的 pip |
| `python3` | `/opt/ctf/bin/python3` → `/opt/venvs/py313/bin/python` | CTF 主 Python 3.13（交互 shell 默认） |
| `pip3` | `/opt/ctf/bin/pip3` → `/opt/venvs/py313/bin/pip` | CTF 主 pip（py313，交互 shell 默认） |
| `python` | `/opt/ctf/bin/python` → `/opt/venvs/py313/bin/python` | CTF 主 Python 3.13（uv venv） |
| `pip` | `/opt/ctf/bin/pip` → `/opt/venvs/py313/bin/pip` | CTF 主 pip（py313） |
| `python2` | `/opt/ctf/bin/python2` → `/usr/local/bin/python2` | micromamba `py27` 环境的 Python 2.7 |
| `pip2` | `/opt/ctf/bin/pip2` → `/usr/local/bin/pip2` | micromamba `py27` 环境的 pip |
| `py27` | `/opt/ctf/bin/py27` → `/usr/local/bin/py27` | Python 2.7 备用入口（等价 `python2`） |
| `uv` | `/usr/local/bin/uv` | Python 3.13 的包/解释器管理器 |
| `micromamba` | `/usr/local/bin/micromamba` | Python 2.7 备用环境管理 |
| `flatter` | `/usr/local/bin/flatter` | LLL 加速 |
| `r2` | `/usr/local/bin/r2` | radare2 |
| `tshark` | `/usr/bin/tshark` | 抓包/PCAP 工具 |
| `java` | `/usr/bin/java` | Java runtime（headless） |
| `node` | `/usr/local/bin/node` | Node.js（用于 CTF/web tooling） |
| `npm` | `/usr/local/bin/npm` | Node.js 包管理器 |
| `bun` | `/usr/local/bin/bun` | Bun（JS runtime + package manager） |
| `jadx` | `/usr/local/bin/jadx` | JADX CLI（Java 反编译/DEX 工具） |
| `rustc` | `/home/sage/.cargo/bin/rustc` | Rust 编译器（rustup，toolchain 见 `repro.lock`） |
| `cargo` | `/home/sage/.cargo/bin/cargo` | Rust 包管理器 |

### 默认 shell 行为（避免踩坑）

- `docker run --rm -it ... bash`：交互式 `bash` 默认会 `source /opt/ctf/env.sh`，把 `python/python3/pip/pip3` 指向 Python 3.13。
- 关闭自动 source：`export CTF_AUTO_SOURCE=0`
- 不推荐 `source /opt/venvs/py313/bin/activate`：会进一步改动 shell 状态；本仓库已经用 `/opt/ctf/env.sh` 解决 `python/python3` 的默认指向。
- 如需强制使用 Sage 的 `python3/pip3`：用绝对路径 `/home/sage/sage/local/bin/python3`、`/home/sage/sage/local/bin/pip3`，或使用 `sage --python` / `sage --pip`。

### 关键环境变量

- `CTF_PY313=/opt/venvs/py313/bin/python`
- `CTF_PY27=/opt/micromamba/envs/py27/bin/python`

### 我们到底有几个 Python？

- CTF Python 3.13：`/opt/venvs/py313/bin/python`（`uv` venv，默认 `python/python3`）
- Sage Python 3.12.x：`sage --python`（Sage 自带 venv，只影响 Sage 生态）
- 系统 Python（Ubuntu）：`/usr/bin/python3`（一般不用于 CTF）
- Python 2.7（备用）：`/opt/micromamba/envs/py27/bin/python`（默认 `python2/py27`）

### 源码位置（构建时拉取，SHA 在 `repro.lock`）

- `/opt/src/crypto-attacks`
- `/opt/src/gf2bv`
- `/opt/src/flatter`
- `/opt/src/or-tools`
- `/opt/src/radare2`

### 验证脚本

- `/opt/verify/smoke.sh`

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

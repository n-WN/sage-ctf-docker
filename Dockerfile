ARG BASE_IMAGE=debian:13
FROM ${BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

# Sage build configuration
ARG SAGE_REPO="https://github.com/sagemath/sage.git"
ARG SAGE_BRANCH="master"
ARG SAGE_MAKEFLAGS
ARG ENABLE_SAGE=1
ARG SAGE_BUILD_STEP="make"
ARG SAGE_REF=""

ARG UV_VERSION="0.9.21"
ARG MICROMAMBA_VERSION="2.4.0-1"

ARG FLATTER_REPO="https://github.com/keeganryan/flatter.git"
ARG FLATTER_REF=""
ARG RADARE2_REPO="https://github.com/radareorg/radare2.git"
ARG RADARE2_REF=""
ARG GF2BV_REPO="https://github.com/maple3142/gf2bv.git"
ARG GF2BV_REF=""
ARG CRYPTO_ATTACKS_REPO="https://github.com/jvdsn/crypto-attacks.git"
ARG CRYPTO_ATTACKS_REF=""
ARG OR_TOOLS_REPO="https://github.com/google/or-tools.git"
ARG OR_TOOLS_REF=""

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    UV_HTTP_TIMEOUT=300 \
    HOME=/home/sage \
    MAMBA_ROOT_PREFIX=/opt/micromamba

SHELL ["/bin/bash", "-lc"]

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends debconf-utils; \
  echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections; \
  groupadd -r wireshark || true; \
  apt-get install -y --no-install-recommends \
    # basics
    ca-certificates curl wget git bash coreutils findutils xz-utils bzip2 unzip zip \
    # binary analysis tools
    bsdmainutils vim-common xxd file binutils strace ltrace \
    # runtime tools
    default-jre-headless tshark \
    # sage minimal prereqs (+bootstrap)
    binutils make m4 perl flex python3 tar bc gcc g++ gfortran patch pkg-config libz-dev libboost-dev \
    autoconf automake libtool \
    # common build deps for python wheels / crypto toolchain
    python3-venv python3-dev python3-setuptools \
    libssl-dev libffi-dev libbz2-dev liblzma-dev zlib1g-dev \
    libreadline-dev libsqlite3-dev libncurses-dev libgdbm-dev libnsl-dev \
    # flatter deps
    cmake ninja-build \
    libgmp-dev libmpfr-dev libmpc-dev fplll-tools libfplll-dev libeigen3-dev libopenblas-dev \
    # gf2bv deps
    libm4ri-dev \
    # CTF tools
    netcat-traditional imagemagick dnsutils gdb \
    sleuthkit binwalk steghide exiftool \
    tcpdump whois nmap \
    john fcrackzip fdisk parallel \
  ; \
  rm -rf /var/lib/apt/lists/*

# radare2 (r2) - build from source for reproducibility across Debian/Ubuntu bases.
RUN set -eux; \
  rm -rf /opt/src/radare2; \
  git clone --no-tags --filter=blob:none "${RADARE2_REPO}" /opt/src/radare2; \
  cd /opt/src/radare2; \
  if [ -n "${RADARE2_REF}" ]; then git -c advice.detachedHead=false checkout "${RADARE2_REF}"; fi; \
  sys/install.sh --prefix=/usr/local; \
  r2 -v >/dev/null

RUN set -eux; \
  arch="$(uname -m)"; \
  case "$arch" in \
    x86_64) uv_arch="x86_64-unknown-linux-gnu" ;; \
    aarch64|arm64) uv_arch="aarch64-unknown-linux-gnu" ;; \
    *) echo "unsupported arch for uv: $arch" >&2; exit 1 ;; \
  esac; \
  curl -LsS "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${uv_arch}.tar.gz" | tar -xz -C /usr/local/bin --strip-components=1; \
  uv --version

RUN set -eux; \
  arch="$(uname -m)"; \
  case "$arch" in \
    x86_64) mamba_arch="linux-64" ;; \
    aarch64|arm64) mamba_arch="linux-aarch64" ;; \
    *) echo "unsupported arch for micromamba: $arch" >&2; exit 1 ;; \
  esac; \
  curl -LsS "https://github.com/mamba-org/micromamba-releases/releases/download/${MICROMAMBA_VERSION}/micromamba-${mamba_arch}.tar.bz2" | tar -xvj -C /usr/local/bin --strip-components=1 bin/micromamba; \
  micromamba --version

COPY requirements/py313.txt /tmp/requirements-py313.txt
RUN set -eux; \
  uv python install 3.13; \
  uv venv /opt/venvs/py313 --python 3.13; \
  /opt/venvs/py313/bin/python -m pip install --upgrade pip setuptools wheel; \
  uv pip install --python /opt/venvs/py313/bin/python -r /tmp/requirements-py313.txt; \
  /opt/venvs/py313/bin/python -V

# Provide a stable "CTF Python" shim that does NOT override `python3` (to avoid
# interfering with other tooling that expects the system `python3`).
RUN set -eux; \
  mkdir -p /opt/ctf/bin; \
  ln -sfn /opt/venvs/py313/bin/python /opt/ctf/bin/python; \
  ln -sfn /opt/venvs/py313/bin/pip /opt/ctf/bin/pip; \
  :

RUN set -eux; \
  cat > /opt/ctf/env.sh <<'EOF'
#!/usr/bin/env bash
export CTF_PY313=/opt/venvs/py313/bin/python
export PATH=/opt/ctf/bin:"$PATH"
EOF

RUN set -eux; \
  chmod 0755 /opt/ctf/env.sh

COPY requirements/py27.txt /tmp/requirements-py27.txt
RUN set -eux; \
  micromamba create -y -n py27 -c conda-forge python=2.7 pip; \
  micromamba run -n py27 python -V; \
  micromamba run -n py27 python -m pip install --upgrade pip setuptools; \
  micromamba run -n py27 python -m pip install -r /tmp/requirements-py27.txt; \
  printf '#!/usr/bin/env bash\nexec micromamba run -n py27 python \"$@\"\n' > /usr/local/bin/py27; \
  chmod +x /usr/local/bin/py27; \
  micromamba clean -a -y

RUN set -eux; \
  mkdir -p /opt/src /opt/verify; \
  if [ -n "${FLATTER_REF}" ]; then \
    git init /opt/src/flatter; \
    git -C /opt/src/flatter remote add origin "${FLATTER_REPO}"; \
    git -C /opt/src/flatter fetch --depth 1 origin "${FLATTER_REF}"; \
    git -C /opt/src/flatter checkout --detach FETCH_HEAD; \
  else \
    git clone --depth 1 "${FLATTER_REPO}" /opt/src/flatter; \
  fi; \
  cmake -S /opt/src/flatter -B /opt/src/flatter/build -DCMAKE_BUILD_TYPE=Release; \
  cmake --build /opt/src/flatter/build -- -j"$(nproc)"; \
  cmake --install /opt/src/flatter/build; \
  ldconfig; \
  flatter -h >/dev/null

RUN set -eux; \
  if [ -n "${GF2BV_REF}" ]; then \
    git init /opt/src/gf2bv; \
    git -C /opt/src/gf2bv remote add origin "${GF2BV_REPO}"; \
    git -C /opt/src/gf2bv fetch --depth 1 origin "${GF2BV_REF}"; \
    git -C /opt/src/gf2bv checkout --detach FETCH_HEAD; \
  else \
    git clone --depth 1 "${GF2BV_REPO}" /opt/src/gf2bv; \
  fi

RUN set -eux; \
  uv pip install --python /opt/venvs/py313/bin/python /opt/src/gf2bv; \
  /opt/venvs/py313/bin/python -c "from gf2bv import LinearSystem; lin=LinearSystem([1,1,1,1]); a,b,c,d=lin.gens(); assert lin.solve_one([a^b^c^1,b^d,a^c^1]) is not None"

RUN set -eux; \
  if [ -n "${CRYPTO_ATTACKS_REF}" ]; then \
    git init /opt/src/crypto-attacks; \
    git -C /opt/src/crypto-attacks remote add origin "${CRYPTO_ATTACKS_REPO}"; \
    git -C /opt/src/crypto-attacks fetch --depth 1 origin "${CRYPTO_ATTACKS_REF}"; \
    git -C /opt/src/crypto-attacks checkout --detach FETCH_HEAD; \
  else \
    git clone --depth 1 "${CRYPTO_ATTACKS_REPO}" /opt/src/crypto-attacks; \
  fi

COPY patches/crypto-attacks-sage108.patch /opt/patches/crypto-attacks-sage108.patch
RUN set -eux; \
  cd /opt/src/crypto-attacks; \
  git apply /opt/patches/crypto-attacks-sage108.patch

RUN set -eux; \
  if [ -n "${OR_TOOLS_REF}" ]; then \
    git init /opt/src/or-tools; \
    git -C /opt/src/or-tools remote add origin "${OR_TOOLS_REPO}"; \
    git -C /opt/src/or-tools fetch --depth 1 origin "${OR_TOOLS_REF}"; \
    git -C /opt/src/or-tools checkout --detach FETCH_HEAD; \
  else \
    git clone --depth 1 "${OR_TOOLS_REPO}" /opt/src/or-tools; \
  fi

RUN set -eux; \
  groupadd -g 1000 sage; \
  useradd -m -u 1000 -g 1000 -s /bin/bash sage; \
  mkdir -p /opt/sage-src; \
  chown -R sage:sage /opt/src /opt/sage-src /opt/verify

# Source the CTF env in interactive shells by default.
# Disable by setting `CTF_AUTO_SOURCE=0`.
RUN set -eux; \
  # Avoid clobbering PATH in interactive shells (breaks Sage env if present).
  python3 -c 'from pathlib import Path; p=Path("/home/sage/.bashrc");\ntry:\n  lines=p.read_text().splitlines()\nexcept Exception:\n  raise SystemExit(0)\nlines=[l for l in lines if not l.startswith(\"export PATH=/home/sage/sage/local/bin:\")]\np.write_text(\"\\n\".join(lines)+\"\\n\")' || true; \
  grep -qF 'CTF_AUTO_SOURCE' /home/sage/.bashrc 2>/dev/null || cat >> /home/sage/.bashrc <<'EOF'

# --- sage-ctf-docker: source CTF env (python -> py3.13) ---
case "$-" in
  *i*)
    if [ "${CTF_AUTO_SOURCE:-1}" != "0" ] && [ -f /opt/ctf/env.sh ]; then
      source /opt/ctf/env.sh
    fi
    ;;
esac
# ---------------------------------------------------------
EOF

RUN set -eux; \
  chown sage:sage /home/sage/.bashrc

USER sage

# Persist GitHub CLI authentication to container
COPY --chown=sage:sage .gh-config/ /home/sage/.config/gh/

WORKDIR /opt

RUN set -eux; \
  if [ "${ENABLE_SAGE}" = "1" ]; then \
    if [ -n "${SAGE_REF}" ]; then \
      git init /opt/sage-src; \
      git -C /opt/sage-src config core.symlinks true; \
      git -C /opt/sage-src remote add upstream "${SAGE_REPO}"; \
      git -C /opt/sage-src fetch --depth 1 upstream "${SAGE_REF}"; \
      git -C /opt/sage-src checkout --detach FETCH_HEAD; \
    else \
      git clone -c core.symlinks=true --filter blob:none --origin upstream --branch "${SAGE_BRANCH}" --tags "${SAGE_REPO}" /opt/sage-src; \
    fi; \
  fi

WORKDIR /opt/sage-src

RUN set -eux; \
  if [ "${ENABLE_SAGE}" = "1" ] && [ "${SAGE_BUILD_STEP}" != "none" ]; then \
    ./bootstrap; \
  fi

RUN set -eux; \
  if [ "${ENABLE_SAGE}" = "1" ] && [ "${SAGE_BUILD_STEP}" != "none" ]; then \
    if [ -n "${SAGE_MAKEFLAGS:-}" ]; then export MAKEFLAGS="${SAGE_MAKEFLAGS}"; else export MAKEFLAGS="-j$(nproc) -l$(nproc).5"; fi; \
    export V=0; \
    if [ "${SAGE_BUILD_STEP}" = "configure" ] || [ "${SAGE_BUILD_STEP}" = "make" ]; then \
      ./configure; \
    fi; \
    if [ "${SAGE_BUILD_STEP}" = "make" ]; then \
      make; \
    fi; \
  fi

USER root
RUN set -eux; \
  if [ "${ENABLE_SAGE}" = "1" ] && [ "${SAGE_BUILD_STEP}" = "make" ]; then \
    ln -sf /opt/sage-src/sage /usr/local/bin/sage; \
    sage --version; \
  fi

COPY requirements/sage.txt /tmp/requirements-sage.txt
RUN set -eux; \
  if [ "${ENABLE_SAGE}" = "1" ] && [ "${SAGE_BUILD_STEP}" = "make" ]; then \
    SAGE_PY="$(sage --python -c 'import sys; print(sys.executable)')"; \
    "${SAGE_PY}" -m pip install --upgrade pip setuptools wheel; \
    uv pip install --python "${SAGE_PY}" -r /tmp/requirements-sage.txt; \
  fi

RUN set -eux; \
  if [ "${ENABLE_SAGE}" = "1" ] && [ "${SAGE_BUILD_STEP}" = "make" ]; then \
    cd /opt/src/crypto-attacks; \
    # Ensure the project root is the unittest top-level dir, so imports like
    # "from shared import ..." resolve to /opt/src/crypto-attacks/shared.
    sage --python -m unittest discover -s test -t . -v; \
  fi

COPY verify/smoke.sh /opt/verify/smoke.sh
RUN chmod +x /opt/verify/smoke.sh

USER sage
WORKDIR /opt

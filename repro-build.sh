#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${DIR}/repro.lock"

usage() {
  cat <<'EOF'
Usage:
  ./repro-build.sh [--update] [--quick|--configure] [--tag NAME] [--sage-version VER] [--base-image IMAGE] [--dockerfile FILE] [--no-cache] [--skip-smoke]

Modes:
  --quick       Build without Sage (ENABLE_SAGE=0)
  --configure   Build Sage bootstrap+configure only (no 'make')

Reproducibility:
  - First run (or --update) resolves latest upstream refs + tool versions and writes repro.lock
  - Subsequent runs reuse repro.lock to rebuild the exact same environment
EOF
}

UPDATE=0
MODE="full" # full|quick|configure
TAG="debian13-sage-ctf:repro"
SAGE_VERSION="10.8"
BASE_IMAGE_TAG="debian:13"
DOCKERFILE="Dockerfile"
NO_CACHE=0
SKIP_SMOKE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --update) UPDATE=1 ;;
    --quick) MODE="quick" ;;
    --configure) MODE="configure" ;;
    --tag) TAG="${2:?missing --tag value}"; shift ;;
    --sage-version) SAGE_VERSION="${2:?missing --sage-version value}"; shift ;;
    --base-image) BASE_IMAGE_TAG="${2:?missing --base-image value}"; shift ;;
    --dockerfile) DOCKERFILE="${2:?missing --dockerfile value}"; shift ;;
    --no-cache) NO_CACHE=1 ;;
    --skip-smoke) SKIP_SMOKE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

need_cmd docker
need_cmd git
need_cmd python3

default_branch() {
  local repo="$1"
  git ls-remote --symref "$repo" HEAD 2>/dev/null \
    | awk '$1=="ref:" && index($2,"refs/heads/")==1 {sub("refs/heads/","",$2); print $2; exit}'
}

head_sha() {
  local repo="$1"
  local branch
  branch="$(default_branch "$repo")"
  if [ -z "${branch}" ]; then
    echo "failed to detect default branch for $repo" >&2
    exit 1
  fi
  git ls-remote "$repo" "refs/heads/${branch}" | awk '{print $1; exit}'
}

tag_sha() {
  local repo="$1"
  local tag="$2"
  local sha=""

  # Prefer annotated tag deref (^{}) to get the commit SHA.
  sha="$(git ls-remote "$repo" "refs/tags/${tag}^{}" | awk '{print $1; exit}')"
  if [ -n "${sha}" ]; then
    echo "${sha}"
    return 0
  fi

  # Common fallback if upstream uses a 'v' prefix.
  sha="$(git ls-remote "$repo" "refs/tags/v${tag}^{}" | awk '{print $1; exit}')"
  if [ -n "${sha}" ]; then
    echo "${sha}"
    return 0
  fi

  echo "failed to resolve tag ${tag} in ${repo}" >&2
  exit 1
}

latest_git_tag() {
  local repo_url="$1"
  git ls-remote --tags --refs "$repo_url" \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | sed 's/^v//' \
    | grep -E '^[0-9]' \
    | sort -V \
    | tail -n 1
}

resolve_base_image_digest() {
  local image_tag="${1:-debian:13}"
  docker pull "$image_tag" >/dev/null
  python3 - <<PY
import json,subprocess,sys
img="${image_tag}"
out=subprocess.check_output(["docker","image","inspect",img,"--format","{{json .RepoDigests}}"], text=True).strip()
digests=json.loads(out)
if not digests:
    sys.exit("no RepoDigests found for %s" % img)
print(digests[0])
PY
}

resolve_rust_stable_toolchain() {
  python3 - <<'PY'
import tomllib, urllib.request
data = urllib.request.urlopen("https://static.rust-lang.org/dist/channel-rust-stable.toml", timeout=60).read()
doc = tomllib.loads(data.decode("utf-8"))
ver = doc["pkg"]["rust"]["version"].split(" ", 1)[0]
print(ver)
PY
}

resolve_node_lts_version() {
  python3 - <<'PY'
import json, urllib.request
idx = json.load(urllib.request.urlopen("https://nodejs.org/dist/index.json", timeout=60))
lts = [x for x in idx if x.get("lts")]
if not lts:
    raise SystemExit("failed to resolve node LTS from index.json")
ver = lts[0]["version"]
if ver.startswith("v"):
    ver = ver[1:]
print(ver)
PY
}

resolve_node_sha256() {
  local version="${1:?missing node version}"
  local filename="${2:?missing node filename}"
  python3 - <<PY
import urllib.request
version="${version}"
filename="${filename}"
shasums = urllib.request.urlopen(f"https://nodejs.org/dist/v{version}/SHASUMS256.txt", timeout=60).read().decode("utf-8")
for line in shasums.splitlines():
    parts=line.split()
    if len(parts) >= 2 and parts[-1] == filename:
        print(parts[0])
        raise SystemExit(0)
raise SystemExit(f"missing {filename} in SHASUMS256.txt for node v{version}")
PY
}

resolve_bun_version() {
  git ls-remote --tags --refs "https://github.com/oven-sh/bun.git" \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | sed 's/^bun-v//' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1
}

resolve_bun_sha256() {
  local version="${1:?missing bun version}"
  local arch="${2:?missing bun arch (x64|aarch64)}"
  local url="https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-${arch}.zip"
  curl -fsSL "${url}" | sha256sum | awk '{print $1}'
}

resolve_jadx_version() {
  git ls-remote --tags --refs "https://github.com/skylot/jadx.git" \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | sed 's/^v//' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1
}

resolve_jadx_sha256() {
  local version="${1:?missing jadx version}"
  local url="https://github.com/skylot/jadx/releases/download/v${version}/jadx-${version}.zip"
  curl -fsSL "${url}" | sha256sum | awk '{print $1}'
}

write_lock() {
  local sage_repo="https://github.com/sagemath/sage.git"
  local flatter_repo="https://github.com/keeganryan/flatter.git"
  local radare2_repo="https://github.com/radareorg/radare2.git"
  local gf2bv_repo="https://github.com/maple3142/gf2bv.git"
  local cuso_repo="https://github.com/keeganryan/cuso.git"
  local flatn_repo="https://github.com/zksecurity/flatn.git"
  local yafu_repo="https://github.com/bbuhrow/yafu.git"
  local crypto_attacks_repo="https://github.com/jvdsn/crypto-attacks.git"
  local or_tools_repo="https://github.com/google/or-tools.git"

  local base_image uv_version micromamba_version rust_toolchain
  base_image="$(resolve_base_image_digest "${BASE_IMAGE_TAG}")"
  uv_version="$(latest_git_tag "https://github.com/astral-sh/uv.git")"
  micromamba_version="$(latest_git_tag "https://github.com/mamba-org/micromamba-releases.git")"
  rust_toolchain="$(resolve_rust_stable_toolchain)"

  local node_version node_sha_linux_x64 node_sha_linux_arm64
  node_version="$(resolve_node_lts_version)"
  node_sha_linux_x64="$(resolve_node_sha256 "${node_version}" "node-v${node_version}-linux-x64.tar.xz")"
  node_sha_linux_arm64="$(resolve_node_sha256 "${node_version}" "node-v${node_version}-linux-arm64.tar.xz")"

  local bun_version bun_sha_linux_x64 bun_sha_linux_arm64
  bun_version="$(resolve_bun_version)"
  if [ -z "${bun_version}" ]; then
    echo "failed to resolve bun version" >&2
    exit 1
  fi
  bun_sha_linux_x64="$(resolve_bun_sha256 "${bun_version}" "x64")"
  bun_sha_linux_arm64="$(resolve_bun_sha256 "${bun_version}" "aarch64")"

  local jadx_version jadx_sha256
  jadx_version="$(resolve_jadx_version)"
  if [ -z "${jadx_version}" ]; then
    echo "failed to resolve jadx version" >&2
    exit 1
  fi
  jadx_sha256="$(resolve_jadx_sha256 "${jadx_version}")"

  local sage_ref flatter_ref radare2_ref gf2bv_ref cuso_ref flatn_ref yafu_ref crypto_attacks_ref or_tools_ref
  sage_ref="$(tag_sha "$sage_repo" "${SAGE_VERSION}")"
  flatter_ref="$(head_sha "$flatter_repo")"
  radare2_ref="$(head_sha "$radare2_repo")"
  gf2bv_ref="$(head_sha "$gf2bv_repo")"
  cuso_ref="$(head_sha "$cuso_repo")"
  flatn_ref="$(head_sha "$flatn_repo")"
  yafu_ref="$(head_sha "$yafu_repo")"
  crypto_attacks_ref="$(head_sha "$crypto_attacks_repo")"
  or_tools_ref="$(head_sha "$or_tools_repo")"

  cat > "${LOCK_FILE}" <<EOF
# Auto-generated by repro-build.sh at $(date -u +"%Y-%m-%dT%H:%M:%SZ")

BASE_IMAGE="${base_image}"
UV_VERSION="${uv_version}"
MICROMAMBA_VERSION="${micromamba_version}"
RUST_TOOLCHAIN="${rust_toolchain}"

NODE_VERSION="${node_version}"
NODE_SHA256_LINUX_X64="${node_sha_linux_x64}"
NODE_SHA256_LINUX_ARM64="${node_sha_linux_arm64}"

BUN_VERSION="${bun_version}"
BUN_SHA256_LINUX_X64="${bun_sha_linux_x64}"
BUN_SHA256_LINUX_ARM64="${bun_sha_linux_arm64}"

JADX_VERSION="${jadx_version}"
JADX_SHA256="${jadx_sha256}"

SAGE_REPO="${sage_repo}"
SAGE_VERSION="${SAGE_VERSION}"
SAGE_REF="${sage_ref}"

FLATTER_REPO="${flatter_repo}"
FLATTER_REF="${flatter_ref}"

RADARE2_REPO="${radare2_repo}"
RADARE2_REF="${radare2_ref}"

GF2BV_REPO="${gf2bv_repo}"
GF2BV_REF="${gf2bv_ref}"

CUSO_REPO="${cuso_repo}"
CUSO_REF="${cuso_ref}"

FLATN_REPO="${flatn_repo}"
FLATN_REF="${flatn_ref}"

YAFU_REPO="${yafu_repo}"
YAFU_REF="${yafu_ref}"

CRYPTO_ATTACKS_REPO="${crypto_attacks_repo}"
CRYPTO_ATTACKS_REF="${crypto_attacks_ref}"

OR_TOOLS_REPO="${or_tools_repo}"
OR_TOOLS_REF="${or_tools_ref}"
EOF
}

if [ "${UPDATE}" = "1" ] || [ ! -f "${LOCK_FILE}" ]; then
  echo "[repro] writing ${LOCK_FILE}"
  write_lock
fi

# shellcheck disable=SC1090
source "${LOCK_FILE}"

: "${NODE_VERSION:?missing NODE_VERSION in repro.lock (run: ./repro-build.sh --update)}"
: "${NODE_SHA256_LINUX_X64:?missing NODE_SHA256_LINUX_X64 in repro.lock (run: ./repro-build.sh --update)}"
: "${NODE_SHA256_LINUX_ARM64:?missing NODE_SHA256_LINUX_ARM64 in repro.lock (run: ./repro-build.sh --update)}"
: "${BUN_VERSION:?missing BUN_VERSION in repro.lock (run: ./repro-build.sh --update)}"
: "${BUN_SHA256_LINUX_X64:?missing BUN_SHA256_LINUX_X64 in repro.lock (run: ./repro-build.sh --update)}"
: "${BUN_SHA256_LINUX_ARM64:?missing BUN_SHA256_LINUX_ARM64 in repro.lock (run: ./repro-build.sh --update)}"
: "${JADX_VERSION:?missing JADX_VERSION in repro.lock (run: ./repro-build.sh --update)}"
: "${JADX_SHA256:?missing JADX_SHA256 in repro.lock (run: ./repro-build.sh --update)}"

: "${YAFU_REPO:?missing YAFU_REPO in repro.lock (run: ./repro-build.sh --update)}"
: "${YAFU_REF:?missing YAFU_REF in repro.lock (run: ./repro-build.sh --update)}"
: "${CUSO_REPO:?missing CUSO_REPO in repro.lock (run: ./repro-build.sh --update)}"
: "${CUSO_REF:?missing CUSO_REF in repro.lock (run: ./repro-build.sh --update)}"
: "${FLATN_REPO:?missing FLATN_REPO in repro.lock (run: ./repro-build.sh --update)}"
: "${FLATN_REF:?missing FLATN_REF in repro.lock (run: ./repro-build.sh --update)}"

BUILD_ARGS=(
  --build-arg "BASE_IMAGE=${BASE_IMAGE}"
  --build-arg "UV_VERSION=${UV_VERSION}"
  --build-arg "MICROMAMBA_VERSION=${MICROMAMBA_VERSION}"
  --build-arg "RUST_TOOLCHAIN=${RUST_TOOLCHAIN}"
  --build-arg "NODE_VERSION=${NODE_VERSION}"
  --build-arg "NODE_SHA256_LINUX_X64=${NODE_SHA256_LINUX_X64}"
  --build-arg "NODE_SHA256_LINUX_ARM64=${NODE_SHA256_LINUX_ARM64}"
  --build-arg "BUN_VERSION=${BUN_VERSION}"
  --build-arg "BUN_SHA256_LINUX_X64=${BUN_SHA256_LINUX_X64}"
  --build-arg "BUN_SHA256_LINUX_ARM64=${BUN_SHA256_LINUX_ARM64}"
  --build-arg "JADX_VERSION=${JADX_VERSION}"
  --build-arg "JADX_SHA256=${JADX_SHA256}"
  --build-arg "SAGE_REPO=${SAGE_REPO}"
  --build-arg "SAGE_REF=${SAGE_REF}"
  --build-arg "FLATTER_REPO=${FLATTER_REPO}"
  --build-arg "FLATTER_REF=${FLATTER_REF}"
  --build-arg "RADARE2_REPO=${RADARE2_REPO}"
  --build-arg "RADARE2_REF=${RADARE2_REF}"
  --build-arg "GF2BV_REPO=${GF2BV_REPO}"
  --build-arg "GF2BV_REF=${GF2BV_REF}"
  --build-arg "CUSO_REPO=${CUSO_REPO}"
  --build-arg "CUSO_REF=${CUSO_REF}"
  --build-arg "FLATN_REPO=${FLATN_REPO}"
  --build-arg "FLATN_REF=${FLATN_REF}"
  --build-arg "YAFU_REPO=${YAFU_REPO}"
  --build-arg "YAFU_REF=${YAFU_REF}"
  --build-arg "CRYPTO_ATTACKS_REPO=${CRYPTO_ATTACKS_REPO}"
  --build-arg "CRYPTO_ATTACKS_REF=${CRYPTO_ATTACKS_REF}"
  --build-arg "OR_TOOLS_REPO=${OR_TOOLS_REPO}"
  --build-arg "OR_TOOLS_REF=${OR_TOOLS_REF}"
)

case "${MODE}" in
  quick)
    BUILD_ARGS+=(--build-arg ENABLE_SAGE=0)
    ;;
  configure)
    BUILD_ARGS+=(--build-arg SAGE_BUILD_STEP=configure)
    ;;
  full) : ;;
  *) echo "bad mode: ${MODE}" >&2; exit 2 ;;
esac

DOCKER_FLAGS=()
if [ "${NO_CACHE}" = "1" ]; then
  DOCKER_FLAGS+=(--no-cache)
fi

echo "[repro] build tag: ${TAG}"
docker build "${DOCKER_FLAGS[@]}" -f "${DIR}/${DOCKERFILE}" -t "${TAG}" "${BUILD_ARGS[@]}" "${DIR}"

if [ "${SKIP_SMOKE}" != "1" ]; then
  echo "[repro] smoke: ${TAG}"
  docker run --rm --entrypoint bash -t "${TAG}" -lc "/opt/verify/smoke.sh"
fi

echo "[repro] done: ${TAG}"

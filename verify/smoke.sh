#!/usr/bin/env bash
set -euo pipefail

echo "[smoke] python3.13 (uv venv)"
/opt/venvs/py313/bin/python -V
/opt/venvs/py313/bin/python -c "import pwn; print('ok: pwntools')"
/opt/venvs/py313/bin/python -c "import paramiko, rpyc; print('ok: paramiko/rpyc')"
/opt/venvs/py313/bin/python -c "import unicorn; print('ok: unicorn')"
/opt/venvs/py313/bin/python -c "import Crypto, gmpy2, sympy, z3; print('ok: pycryptodome/gmpy2/sympy/z3')"
/opt/venvs/py313/bin/python -c "import cryptography, nacl; print('ok: cryptography/pynacl')"
/opt/venvs/py313/bin/python -c "import ortools; print('ok: ortools')"
/opt/venvs/py313/bin/python -c "import zstandard; print('ok: zstandard')"

echo "[smoke] system tools"
command -v java >/dev/null
java -version >/dev/null 2>&1 || true
command -v r2 >/dev/null
r2 -v >/dev/null
command -v tshark >/dev/null
tshark -v >/dev/null

echo "[smoke] flatter"
command -v flatter >/dev/null
flatter -h >/dev/null

echo "[smoke] gf2bv (py313)"
/opt/venvs/py313/bin/python -c "from gf2bv import LinearSystem; lin=LinearSystem([1,1,1,1]); a,b,c,d=lin.gens(); sol=lin.solve_one([a^b^c^1,b^d,a^c^1]); assert sol is not None; print('ok: gf2bv py313')"

echo "[smoke] sage"
if command -v sage >/dev/null; then
  sage_ver="$(sage --version | tr -d '\r')"
  echo "${sage_ver}"
  if ! echo "${sage_ver}" | grep -qF 'SageMath version 10.8'; then
    echo "[smoke] unexpected Sage version; want 10.8" >&2
    exit 1
  fi
  if echo "${sage_ver}" | grep -qiE '(beta|rc)'; then
    echo "[smoke] unexpected Sage pre-release; want stable 10.8" >&2
    exit 1
  fi
  sage -c "print('ok: sage', (2+2))"
  sage -python -c "import Crypto; print('ok: sage pycryptodome')"
  sage -python -c "import pwn; print('ok: sage pwntools')"
  sage -python -c "import paramiko, rpyc; print('ok: sage paramiko/rpyc')"
  sage -python -c "import unicorn; print('ok: sage unicorn')"
  sage -python -c "import cryptography, nacl; print('ok: sage cryptography/pynacl')"
  sage -python -c "import z3; print('ok: sage z3')"
  sage -python -c "import zstandard; print('ok: sage zstandard')"
else
  echo "[smoke] sage missing; skip sage checks (build with SAGE_BUILD_STEP=make)" >&2
fi

echo "[smoke] crypto-attacks unit tests (sage -python)"
if command -v sage >/dev/null; then
  cd /opt/src/crypto-attacks
  sage -python -m unittest discover -s test -t . -v
else
  echo "[smoke] sage missing; skip crypto-attacks tests (build with SAGE_BUILD_STEP=make)" >&2
fi

echo "[smoke] python2.7 (micromamba env)"
if [ -x /usr/local/bin/py27 ]; then
  /usr/local/bin/py27 -V
  /usr/local/bin/py27 -c "import requests; print('ok: py27 requests')"
  /usr/local/bin/py27 -c "import Crypto; print('ok: py27 pycryptodome')"
  /usr/local/bin/py27 -c "import sympy; print('ok: py27 sympy')"
else
  echo "[smoke] py27 wrapper missing" >&2
  exit 1
fi

echo "[smoke] all ok"

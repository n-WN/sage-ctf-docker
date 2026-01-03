#!/usr/bin/env bash
set -euo pipefail

echo "[smoke] python3.13 (uv venv)"
/opt/venvs/py313/bin/python -c "import os; assert os.environ.get('HOME') in ('/home/sage','/root'); print('ok: HOME=' + os.environ.get('HOME',''))"
/opt/venvs/py313/bin/python -V
/opt/venvs/py313/bin/python -c "import pwn; print('ok: pwntools')"
/opt/venvs/py313/bin/python -c "import paramiko, rpyc; print('ok: paramiko/rpyc')"
/opt/venvs/py313/bin/python -c "import unicorn; print('ok: unicorn')"
/opt/venvs/py313/bin/python -c "import Crypto, gmpy2, sympy, z3; print('ok: pycryptodome/gmpy2/sympy/z3')"
/opt/venvs/py313/bin/python -c "import cryptography, nacl; print('ok: cryptography/pynacl')"
/opt/venvs/py313/bin/python -c "import ortools; print('ok: ortools')"
/opt/venvs/py313/bin/python -c "import zstandard; print('ok: zstandard')"
/opt/venvs/py313/bin/python -c "import flask, httpx; print('ok: flask/httpx')"
/opt/venvs/py313/bin/python -c "import scipy; print('ok: scipy', scipy.__version__)"
/opt/venvs/py313/bin/python -c "import gmsm; print('ok: gmsm')"
/opt/venvs/py313/bin/python -c "import flatn; out=flatn.reduce([[1,0,331,303],[0,1,456,225],[0,0,628,0],[0,0,0,628]]); assert len(out)==4 and len(out[0])==4; print('ok: flatn')"

echo "[smoke] ctf shim + bashrc wiring"
test -x /opt/ctf/env.sh
test -x /opt/ctf/bin/python
test -x /opt/ctf/bin/python3
test -x /opt/ctf/bin/pip3
test -x /opt/ctf/bin/sage
test -x /opt/ctf/bin/python2
test -x /opt/ctf/bin/pip2
/opt/ctf/bin/python -V | grep -qF 'Python 3.13'
grep -qF 'source /opt/ctf/env.sh' /home/sage/.bashrc
! grep -qE '^export PATH=/home/sage/sage/local/bin:' /home/sage/.bashrc
bash -ic 'python -V' 2>&1 | grep -qF 'Python 3.13'
bash -ic 'python3 -V' 2>&1 | grep -qF 'Python 3.13'
bash -ic 'pip3 -V' 2>&1 | grep -qF '(python 3.13)'
bash -ic 'command -v python3' 2>&1 | grep -qF '/opt/ctf/bin/python3'
bash -ic 'python3 -c "import sys; assert sys.prefix==\"/opt/venvs/py313\"; import pwn; print(\"ok: bashrc python3 pwntools\")"' >/dev/null
bash -ic 'python -c "import pwn; print(\"ok: bashrc python pwntools\")"' >/dev/null
bash -ic 'command -v sage' 2>&1 | grep -qF '/opt/ctf/bin/sage'
bash -ic 'sage --version' 2>&1 | grep -qF 'SageMath version 10.8'
bash -ic 'python2 -V' 2>&1 | grep -qF 'Python 2.7'
bash -ic 'pip2 -V' 2>&1 | grep -qF '(python 2.7'
if command -v sage >/dev/null; then
  sage --python -V | grep -qF 'Python 3.12'
fi

echo "[smoke] system tools"
command -v rg >/dev/null
rg --version >/dev/null
command -v fd >/dev/null
fd --version >/dev/null
command -v java >/dev/null
java -version >/dev/null 2>&1 || true
command -v nc >/dev/null
command -v node >/dev/null
node --version
command -v npm >/dev/null
npm --version
command -v bun >/dev/null
bun --version
command -v pdftotext >/dev/null
pdftotext -v >/dev/null 2>&1 || true
command -v jadx >/dev/null
jadx --help >/dev/null
command -v rustc >/dev/null
command -v cargo >/dev/null
rustc --version
cargo --version
command -v r2 >/dev/null
r2 -v >/dev/null
command -v tshark >/dev/null
tshark -v >/dev/null

command -v strace >/dev/null
strace -V >/dev/null
command -v gdb >/dev/null
gdb --version >/dev/null

echo "[smoke] flatter"
command -v flatter >/dev/null
flatter -h >/dev/null

echo "[smoke] yafu"
command -v yafu >/dev/null
printf 'factor(2021)\n' | yafu >/dev/null

echo "[smoke] gf2bv (py313)"
/opt/venvs/py313/bin/python -c "from gf2bv import LinearSystem; lin=LinearSystem([1,1,1,1]); a,b,c,d=lin.gens(); sol=lin.solve_one([a^b^c^1,b^d,a^c^1]); assert sol is not None; print('ok: gf2bv py313')"

echo "[smoke] sage"
if command -v sage >/dev/null; then
  python3 -V
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
  sage --python -c "import Crypto; print('ok: sage pycryptodome')"
  sage --python -c "import pwn; print('ok: sage pwntools')"
  sage --python -c "import paramiko, rpyc; print('ok: sage paramiko/rpyc')"
  sage --python -c "import unicorn; print('ok: sage unicorn')"
  sage --python -c "import cryptography, nacl; print('ok: sage cryptography/pynacl')"
  sage --python -c "import z3; print('ok: sage z3')"
  sage --python -c "import zstandard; print('ok: sage zstandard')"
  sage --python -c "import flatn; out=flatn.reduce([[1,0,331,303],[0,1,456,225],[0,0,628,0],[0,0,0,628]]); assert len(out)==4; print('ok: sage flatn')"
  sage --python -c "import cuso; from sage.all import var; x=var('x'); solns=cuso.find_small_roots([x^2 - 1], {x: 2}); assert any(int(s[x]) in (-1, 1) for s in solns); print('ok: sage cuso')"
else
  echo "[smoke] sage missing; skip sage checks (build with SAGE_BUILD_STEP=make)" >&2
fi

echo "[smoke] crypto-attacks unit tests (sage --python)"
if command -v sage >/dev/null; then
  cd /opt/src/crypto-attacks
  sage --python -m unittest discover -s test -t . -v
else
  echo "[smoke] sage missing; skip crypto-attacks tests (build with SAGE_BUILD_STEP=make)" >&2
fi

echo "[smoke] python2.7 (micromamba env)"
if [ -x /usr/local/bin/py27 ]; then
  /usr/local/bin/py27 -V
  command -v python2 >/dev/null
  python2 -V
  command -v pip2 >/dev/null
  pip2 -V | grep -qF '(python 2.7'
  /usr/local/bin/py27 -c "import requests; print('ok: py27 requests')"
  /usr/local/bin/py27 -c "import Crypto; print('ok: py27 Crypto')"
  /usr/local/bin/py27 -c "import pkg_resources; assert pkg_resources.get_distribution('pycryptodome').version.startswith('3.'); print('ok: py27 pycryptodome')"
  ! /usr/local/bin/py27 -c "import pkg_resources; pkg_resources.get_distribution('pycrypto')" >/dev/null 2>&1
  /usr/local/bin/py27 -c "import sympy; print('ok: py27 sympy')"
  /usr/local/bin/py27 -c "import gmpy2; print('ok: py27 gmpy2')"
  PWNLIB_NOTERM=1 /usr/local/bin/py27 -c "import pwn; print('ok: py27 pwntools')"
else
  echo "[smoke] py27 wrapper missing" >&2
  exit 1
fi

echo "[smoke] all ok"

#!/usr/bin/env bash
set -u

PASS=0
FAIL=0

test_tool() {
    local name="$1"
    local cmd="${2:-$1}"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $name"
        ((PASS++))
    else
        echo "  ✗ $name"
        ((FAIL++))
    fi
}

test_python_module() {
    local env="$1"
    local module="$2"
    local python_cmd="$3"
    
    if $python_cmd -c "import $module" >/dev/null 2>&1; then
        echo "  ✓ $env: $module"
        ((PASS++))
        return 0
    else
        echo "  ✗ $env: $module"
        ((FAIL++))
        return 1
    fi
}

test_python_function() {
    local env="$1"
    local test_code="$2"
    local python_cmd="$3"
    
    if $python_cmd << EOF >/dev/null 2>&1
$test_code
EOF
    then
        echo "  ✓ $env: functional test"
        ((PASS++))
    else
        echo "  ✗ $env: functional test"
        ((FAIL++))
    fi
}

echo "=== SAGE-CTF SMOKE TESTS ==="
echo ""

echo "Python Environments:"
test_python_module "py313" "numpy" "/opt/venvs/py313/bin/python"
test_python_module "py313" "reedsolo" "/opt/venvs/py313/bin/python"
test_python_module "py27" "numpy" "micromamba run -n py27 python"
test_python_module "py27" "reedsolo" "micromamba run -n py27 python"
test_python_module "sage" "numpy" "sage --python"
test_python_module "sage" "reedsolo" "sage --python"

echo ""
echo "Python Functional Tests:"
test_python_function "py313 numpy" "
import numpy as np
arr = np.array([1, 2, 3])
assert len(arr) == 3
" "/opt/venvs/py313/bin/python"

test_python_function "py313 reedsolo" "
from reedsolo import RSCodec
rsc = RSCodec(10)
enc = rsc.encode(b'test')
assert len(enc[0]) > 0
" "/opt/venvs/py313/bin/python"

test_python_function "py27 numpy" "
import numpy as np
arr = np.array([1, 2, 3])
" "micromamba run -n py27 python"

test_python_function "py27 reedsolo" "
from reedsolo import RSCodec
rsc = RSCodec(10)
" "micromamba run -n py27 python"

test_python_function "sage numpy" "
import numpy as np
arr = np.array([1, 2, 3])
" "sage --python"

test_python_function "sage reedsolo" "
from reedsolo import RSCodec
rsc = RSCodec(10)
" "sage --python"

echo ""
echo "System Tools (Binary Analysis):"
test_tool "gdb"
test_tool "file"
test_tool "binutils" "objdump"
test_tool "strace"
test_tool "ltrace"
test_tool "xxd"

echo ""
echo "System Tools (CTF):"
test_tool "netcat-traditional" "nc"
test_tool "imagemagick" "convert"
test_tool "dnsutils" "dig"
test_tool "sleuthkit" "fls"
test_tool "binwalk"
test_tool "steghide"
test_tool "exiftool"
test_tool "tcpdump"
test_tool "tshark"
test_tool "whois"
test_tool "nmap"
test_tool "john"
test_tool "fcrackzip"
test_tool "fdisk"
test_tool "parallel"

echo ""
echo "System Tools (Build):"
test_tool "gcc"
test_tool "make"
test_tool "git"
test_tool "wget"
test_tool "curl"

echo ""
echo "Libraries:"
test_tool "libgmp" "gmp-info"
test_tool "libmpc"

echo ""
echo "=== RESULTS ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ $FAIL -eq 0 ]; then
    echo "✓ All smoke tests passed"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi

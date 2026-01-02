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

## crypto-attacks 题型索引

该镜像内置 `jvdsn/crypto-attacks`（源码：`/opt/src/crypto-attacks`，与 `repro.lock` 固定的 SHA 一致）。常见用法：

- 直接运行某个脚本：`sage --python attacks/<category>/<name>.py`（参考 upstream README 的示例方式，在文件末尾补充参数后运行）
- 在你自己的脚本里调用：`from attacks.<category> import <module>; <module>.<fn>(...)`（最常见入口是 `attack(...)`，少数模块用 `factorize(...)` / `recover(...)` 等）

下表按 upstream README 的分类列出 `attacks/` 下每个脚本的“主入口函数签名”，并附上 upstream `test/` 中的参考调用（便于对照你要填的参数形状）。

<details>
<summary>展开/收起：crypto-attacks 全量题型表（76 行）</summary>

| 分类 | 题型/攻击 | 入口 (文件/模块) | 主函数 | 参考调用（来自 upstream tests） |
|---|---|---|---|---|
| Approximate Common Divisor | Multivariate polynomial attack | `attacks/acd/mp.py`<br>`attacks.acd.mp` | `attack(N, a, rho, t=1, k=1, roots_method='groebner')` | `mp.attack(N, a, rho)` |
| Approximate Common Divisor | Orthogonal based attack | `attacks/acd/ol.py`<br>`attacks.acd.ol` | `attack(x, rho)` | `ol.attack(x, rho)` |
| Approximate Common Divisor | Simultaneous Diophantine approximation attack | `attacks/acd/sda.py`<br>`attacks.acd.sda` | `attack(x, rho)` | `sda.attack(x, rho)` |
| CBC | Bit flipping attack | `attacks/cbc/bit_flipping.py`<br>`attacks.cbc.bit_flipping` | `attack(iv, c, pos, p, p_)` | `bit_flipping.attack(iv, c, 0, p[0:len(p_)], p_)` |
| CBC | IV recovery attack | `attacks/cbc/iv_recovery.py`<br>`attacks.cbc.iv_recovery` | `attack(decrypt_oracle)` | `iv_recovery.attack(lambda c: self._decrypt(key, iv, c))` |
| CBC | Padding oracle attack | `attacks/cbc/padding_oracle.py`<br>`attacks.cbc.padding_oracle` | `attack(padding_oracle, iv, c)` | `padding_oracle.attack(lambda iv, c: self._valid_padding(key, iv, c), iv, c)` |
| CBC + CBC-MAC | Key reuse attack (encrypt-and-MAC) | `attacks/cbc_and_cbc_mac/eam_key_reuse.py`<br>`attacks.cbc_and_cbc_mac.eam_key_reuse` | `attack(decrypt_oracle, iv, c, t)` | `eam_key_reuse.attack(lambda iv, c, t: self._decrypt_eam(key, iv, c, t), iv, c, t)` |
| CBC + CBC-MAC | Key reuse attack (encrypt-then-MAC) | `attacks/cbc_and_cbc_mac/etm_key_reuse.py`<br>`attacks.cbc_and_cbc_mac.etm_key_reuse` | `attack(encrypt_oracle, decrypt_oracle, iv, c, t)` | `etm_key_reuse.attack(lambda p: self._encrypt_etm(key, p), lambda iv, c, t: self._decrypt_etm(key, iv, c, t), iv, c, t)` |
| CBC + CBC-MAC | Key reuse attack (MAC-then-encrypt) | `attacks/cbc_and_cbc_mac/mte_key_reuse.py`<br>`attacks.cbc_and_cbc_mac.mte_key_reuse` | `attack(decrypt_oracle, iv, c, encrypted_zeroes)` | `mte_key_reuse.attack(lambda iv, c: self._decrypt_mte(key, iv, c), iv, c, encrypted_zeroes)` |
| CBC-MAC | Length extension attack | `attacks/cbc_mac/length_extension.py`<br>`attacks.cbc_mac.length_extension` | `attack(m1, t1, m2, t2)` | `length_extension.attack(m1, t1, m2, t2)` |
| CTR | Bit flipping attack | `attacks/ctr/bit_flipping.py`<br>`attacks.ctr.bit_flipping` | `attack(c, pos, p, p_)` | `bit_flipping.attack(c, 0, p[0:len(p_)], p_)` |
| CTR | CRIME attack | `attacks/ctr/crime.py`<br>`attacks.ctr.crime` | `attack(encrypt_oracle, known_prefix, padding_byte)` | `crime.attack(...)` |
| CTR | Separator oracle attack | `attacks/ctr/separator_oracle.py`<br>`attacks.ctr.separator_oracle` | `attack(separator_oracle, separator_byte, c)` | `separator_oracle.attack(lambda c: self._valid_separators(separator_byte, separator_count, key, c), separator_byte, c)` |
| ECB | Plaintext recovery attack | `attacks/ecb/plaintext_recovery.py`<br>`attacks.ecb.plaintext_recovery` | `attack(encrypt_oracle, unused_byte=0)` | `plaintext_recovery.attack(lambda p: self._encrypt(key, pad(p + s, 16)))` |
| ECB | Plaintext recovery attack (harder variant) | `attacks/ecb/plaintext_recovery_harder.py`<br>`attacks.ecb.plaintext_recovery_harder` | `attack(encrypt_oracle, unused_byte=0)` | `plaintext_recovery_harder.attack(lambda p: self._encrypt(key, pad(prefix + p + s, 16)))` |
| ECB | Plaintext recovery attack (hardest variant) | `attacks/ecb/plaintext_recovery_hardest.py`<br>`attacks.ecb.plaintext_recovery_hardest` | `attack(encrypt_oracle, unused_byte=0)` | `plaintext_recovery_hardest.attack(lambda p: self._encrypt(key, pad(self._randbytes(randrange(0, 16)) + p + s, 16)))` |
| Elliptic Curve Cryptography | ECDSA nonce reuse attack | `attacks/ecc/ecdsa_nonce_reuse.py`<br>`attacks.ecc.ecdsa_nonce_reuse` | `attack(n, m1, r1, s1, m2, r2, s2)` | `ecdsa_nonce_reuse.attack(n, m1, r, s1, m2, r, s2)` |
| Elliptic Curve Cryptography | Frey-Ruck attack | `attacks/ecc/frey_ruck_attack.py`<br>`attacks.ecc.frey_ruck_attack` | `attack(P, R, max_k=6, max_tries=10)` | `frey_ruck_attack.attack(P, R)` |
| Elliptic Curve Cryptography | MOV attack | `attacks/ecc/mov_attack.py`<br>`attacks.ecc.mov_attack` | `attack(P, R, max_k=6, max_tries=10)` | `mov_attack.attack(P, R)` |
| Elliptic Curve Cryptography | Parameter recovery | `attacks/ecc/parameter_recovery.py`<br>`attacks.ecc.parameter_recovery` | `attack(p, x1, y1, x2, y2)` | `parameter_recovery.attack(p, x1, y1, x2, y2)` |
| Elliptic Curve Cryptography | Singular curve attack | `attacks/ecc/singular_curve.py`<br>`attacks.ecc.singular_curve` | `attack(p, a2, a4, a6, Gx, Gy, Px, Py)` | `singular_curve.attack(p, a2, a4, a6, Gx, Gy, Px, Py)` |
| Elliptic Curve Cryptography | Smart's attack (with curves over extension fields) | `attacks/ecc/smart_attack.py`<br>`attacks.ecc.smart_attack` | `attack(G, P)` | `smart_attack.attack(G, l * G)` |
| ElGamal Encryption | Nonce reuse attack | `attacks/elgamal_encryption/nonce_reuse.py`<br>`attacks.elgamal_encryption.nonce_reuse` | `attack(p, m, c1, c2, c1_, c2_)` | `nonce_reuse.attack(p, m, c1, c2, c1_, c2_)` |
| ElGamal Encryption | Unsafe generator attack | `attacks/elgamal_encryption/unsafe_generator.py`<br>`attacks.elgamal_encryption.unsafe_generator` | `attack(p, h, c1, c2)` | `unsafe_generator.attack(p, h, c1, c2)` |
| ElgGamal Signature | Nonce reuse attack | `attacks/elgamal_signature/nonce_reuse.py`<br>`attacks.elgamal_signature.nonce_reuse` | `attack(p, m1, r1, s1, m2, r2, s2)` | `nonce_reuse.attack(p, m1, r, s1, m2, r, s2)` |
| Factorization | Base conversion factorization | `attacks/factorization/base_conversion.py`<br>`attacks.factorization.base_conversion` | `factorize(N, coefficient_threshold=32)` | `base_conversion.factorize(N)` |
| Factorization | Branch and prune attack | `attacks/factorization/branch_and_prune.py`<br>`attacks.factorization.branch_and_prune` | `factorize_pq(N, p, q)` | `branch_and_prune.factorize_pq(N, PartialInteger.from_bits_be(p_bits), PartialInteger.from_bits_be(q_bits))` |
| Factorization | Complex multiplication (elliptic curve) factorization | `attacks/factorization/complex_multiplication.py`<br>`attacks.factorization.complex_multiplication` | `factorize(N, D)` | `complex_multiplication.factorize(N, D)` |
| Factorization | Coppersmith factorization | `attacks/factorization/coppersmith.py`<br>`attacks.factorization.coppersmith` | `factorize_p(N, partial_p, beta=0.5, epsilon=0.125, m=None, t=None)` | `coppersmith.factorize_p(N, PartialInteger.msb_of(p, 512, 280), m=6, t=6)` |
| Factorization | Fermat factorization | `attacks/factorization/fermat.py`<br>`attacks.factorization.fermat` | `factorize(N)` | `fermat.factorize(N)` |
| Factorization | Ghafar-Ariffin-Asbullah attack | `attacks/factorization/gaa.py`<br>`attacks.factorization.gaa` | `factorize(N, rp, rq)` | `gaa.factorize(N, rp, rq)` |
| Factorization | Implicit factorization | `attacks/factorization/implicit.py`<br>`attacks.factorization.implicit` | `factorize_msb(N, n, t)` | `implicit.factorize_msb(N, p_bit_length + q_bit_length, t)` |
| Factorization | Known phi factorization | `attacks/factorization/known_phi.py`<br>`attacks.factorization.known_phi` | `factorize(N, phi)` | `known_phi.factorize(N, phi)` |
| Factorization | ROCA | `attacks/factorization/roca.py`<br>`attacks.factorization.roca` | `factorize(N, M, m, t, g=65537)` | `roca.factorize(N, M, 5, 6)` |
| Factorization | Shor's algorithm (classical) | `attacks/factorization/shor.py`<br>`attacks.factorization.shor` | `factorize(N, a, s)` | `shor.factorize(N, 751228, 78)` |
| Factorization | Twin primes factorization | `attacks/factorization/twin_primes.py`<br>`attacks.factorization.twin_primes` | `factorize(N)` | `twin_primes.factorize(N)` |
| Factorization | Factorization of unbalanced moduli | `attacks/factorization/unbalanced.py`<br>`attacks.factorization.unbalanced` | `factorize(N, partial_p, Q, m=1, t=None, check_bounds=True)` | `unbalanced.factorize(N, partial_p, 256, m=1, t=0)` |
| GCM | Forbidden attack | `attacks/gcm/forbidden_attack.py`<br>`attacks.gcm.forbidden_attack` | `recover_possible_auth_keys(a1, c1, t1, a2, c2, t2)` | `forbidden_attack.recover_possible_auth_keys(a1, c1, t1, a2, c2, t2)` |
| Hidden Number Problem | Extended hidden number problem | `attacks/hnp/extended_hnp.py`<br>`attacks.hnp.extended_hnp` | `dsa_known_bits(N, h, r, s, x, k)` | `extended_hnp.dsa_known_bits(p, h, r, s, PartialInteger.unknown(k_bit_length), partial_k)` |
| Hidden Number Problem | Lattice-based attack | `attacks/hnp/lattice_attack.py`<br>`attacks.hnp.lattice_attack` | `dsa_known_msb(n, h, r, s, k)` | `lattice_attack.dsa_known_msb(p, h, r, s, partial_k)` |
| IGE | Padding oracle attack | `attacks/ige/padding_oracle.py`<br>`attacks.ige.padding_oracle` | `attack(padding_oracle, p0, c0, c)` | `padding_oracle.attack(lambda p0, c0, c: self._valid_padding(key, p0, c0, c), p0, c0, c)` |
| Knapsack Cryptosystems | Low density attack | `attacks/knapsack/low_density.py`<br>`attacks.knapsack.low_density` | `attack(a, s)` | `low_density.attack(a, s)` |
| Linear Congruential Generators | LCG parameter recovery | `attacks/lcg/parameter_recovery.py`<br>`attacks.lcg.parameter_recovery` | `attack(y, m=None, a=None, c=None)` | `parameter_recovery.attack(y)` |
| Linear Congruential Generators | Truncated LCG parameter recovery | `attacks/lcg/truncated_parameter_recovery.py`<br>`attacks.lcg.truncated_parameter_recovery` | `attack(y, k, s, m=None, a=None, check_modulus=None)` | `truncated_parameter_recovery.attack(y, k, s)` |
| Linear Congruential Generators | Truncated LCG state recovery | `attacks/lcg/truncated_state_recovery.py`<br>`attacks.lcg.truncated_state_recovery` | `attack(y, k, s, m, a, c)` | `truncated_state_recovery.attack(y, k, s, m, a, c)` |
| Learning With Errors | Arora-Ge attack | `attacks/lwe/arora_ge.py`<br>`attacks.lwe.arora_ge` | `attack(q, A, b, E, S=None)` | `arora_ge.attack(q, A, b, E)` |
| Mersenne Twister | State recovery | `attacks/mersenne_twister/state_recovery.py`<br>`attacks.mersenne_twister.state_recovery` | `attack_mt19937(y)` | `state_recovery.attack_mt19937(y)` |
| One-time Pad | Key reuse | `attacks/otp/key_reuse.py`<br>`attacks.otp.key_reuse` | `attack(c, char_frequencies, char_floor, key_size=None)` | `key_reuse.attack(c, char_frequencies, char_floor, key_size=key_size)` |
| Pseudoprimes | Generating Miller-Rabin pseudoprimes | `attacks/pseudoprimes/miller_rabin.py`<br>`attacks.pseudoprimes.miller_rabin` | `generate_pseudoprime(A, k2=None, k3=None, min_bit_length=0)` | `miller_rabin.generate_pseudoprime(bases, min_bit_length=400)` |
| RC4 | Fluhrer-Mantin-Shamir attack | `attacks/rc4/fms.py`<br>`attacks.rc4.fms` | `attack(encrypt_oracle, key_len)` | `fms.attack(lambda iv, p: self._encrypt(iv, key, p), len(key))` |
| RSA | Bleichenbacher's attack | `attacks/rsa/bleichenbacher.py`<br>`attacks.rsa.bleichenbacher` | `attack(padding_oracle, n, e, c)` | `bleichenbacher.attack(lambda c: self._valid_padding_v1_5(cipher, k, c, sentinel), n, e, c)` |
| RSA | Bleichenbacher's signature forgery attack | `attacks/rsa/bleichenbacher_signature_forgery.py`<br>`attacks.rsa.bleichenbacher_signature_forgery` | `attack(suffix, suffix_bit_length)` | `bleichenbacher_signature_forgery.attack(suffix, suffix_bit_length)` |
| RSA | Boneh-Durfee attack | `attacks/rsa/boneh_durfee.py`<br>`attacks.rsa.boneh_durfee` | `attack(N, e, factor_bit_length, partial_p=None, delta=0.25, m=1, t=None)` | `boneh_durfee.attack(N, e, 512, delta=0.26, m=3, t=1)` |
| RSA | Cherkaoui-Semmouni's attack | `attacks/rsa/cherkaoui_semmouni.py`<br>`attacks.rsa.cherkaoui_semmouni` | `attack(N, e, beta, delta, m=1, t=None, check_bounds=True)` | `cherkaoui_semmouni.attack(N, e, beta, delta, m=5)` |
| RSA | Common modulus attack | `attacks/rsa/common_modulus.py`<br>`attacks.rsa.common_modulus` | `attack(n, e1, c1, e2, c2)` | `common_modulus.attack(n, e1, c1, e2, c2)` |
| RSA | CRT fault attack | `attacks/rsa/crt_fault_attack.py`<br>`attacks.rsa.crt_fault_attack` | `attack_known_m(n, e, m, s)` | `crt_fault_attack.attack_known_m(n, e, 2, self._crt_faulty_sign(2, p, q, d))` |
| RSA | d fault attack | `attacks/rsa/d_fault_attack.py`<br>`attacks.rsa.d_fault_attack` | `attack(n, e, sv, sf)` | `d_fault_attack.attack(n, e, sv, sf)` |
| RSA | Desmedt-Odlyzko attack (selective forgery) | `attacks/rsa/desmedt_odlyzko.py`<br>`attacks.rsa.desmedt_odlyzko` | `attack(hash_oracle, sign_oracle, N, e, target_m)` | `desmedt_odlyzko.attack(hash_oracle, sign_oracle, N, e, m)` |
| RSA | Extended Wiener's attack | `attacks/rsa/extended_wiener_attack.py`<br>`attacks.rsa.extended_wiener_attack` | `attack(n, e, max_s=20000, max_r=100, max_t=100)` | `extended_wiener_attack.attack(n, e)` |
| RSA | Hastad's broadcast attack | `attacks/rsa/hastad_attack.py`<br>`attacks.rsa.hastad_attack` | `attack(N, e, c)` | `hastad_attack.attack(N, e, c)` |
| RSA | Known CRT exponents attack | `attacks/rsa/known_crt_exponents.py`<br>`attacks.rsa.known_crt_exponents` | `attack(e_start, e_end, N=None, dp=None, dq=None, p_bit_length=None, q_bit_length=None)` | `known_crt_exponents.attack(e, e + 2, N=N, dp=dp, dq=dq)` |
| RSA | Partial known CRT exponents attack | `attacks/rsa/known_crt_exponents.py`<br>`attacks.rsa.known_crt_exponents` | `attack(e_start, e_end, N=None, dp=None, dq=None, p_bit_length=None, q_bit_length=None)` | `known_crt_exponents.attack(e, e + 2, N=N, dp=dp, dq=dq)` |
| RSA | Known private exponent attack | `attacks/rsa/known_d.py`<br>`attacks.rsa.known_d` | `attack(N, e, d)` | `known_d.attack(N, e, d)` |
| RSA | Low public exponent attack | `attacks/rsa/low_exponent.py`<br>`attacks.rsa.low_exponent` | `attack(e, c)` | `low_exponent.attack(e, c)` |
| RSA | LSB oracle (parity oracle) attack | `attacks/rsa/lsb_oracle.py`<br>`attacks.rsa.lsb_oracle` | `attack(N, e, c, oracle)` | `lsb_oracle.attack(N, e, c, lambda c: pow(c, d, N) & 1)` |
| RSA | Manger's attack | `attacks/rsa/manger.py`<br>`attacks.rsa.manger` | `attack(padding_oracle, n, e, c)` | `manger.attack(lambda c: self._valid_padding_oaep(n, d, B, c), n, e, c)` |
| RSA | Nitaj's CRT-RSA attack | `attacks/rsa/nitaj_crt_rsa.py`<br>`attacks.rsa.nitaj_crt_rsa` | `attack(N, e, delta, m, t, check_bounds=True)` | `nitaj_crt_rsa.attack(N, e, 0.09, m=4, t=2)` |
| RSA | Non coprime public exponent attack | `attacks/rsa/non_coprime_exponent.py`<br>`attacks.rsa.non_coprime_exponent` | `attack(N, e, phi, c)` | `non_coprime_exponent.attack(N, e, phi, c)` |
| RSA | Partial key exposure | `attacks/rsa/partial_key_exposure.py`<br>`attacks.rsa.partial_key_exposure` | `attack(N, e, partial_d, factor_e=True, m=1, t=None)` | `partial_key_exposure.attack(N, e, PartialInteger.lsb_and_msb_of(d, 1024, 300, 400), m=4, t=4)` |
| RSA | Related message attack | `attacks/rsa/related_message.py`<br>`attacks.rsa.related_message` | `attack(N, e, c1, c2, f1, f2)` | `related_message.attack(N, e, c1, c2, lambda x: x, lambda x: (x - 1) / 2)` |
| RSA | Stereotyped message attack | `attacks/rsa/stereotyped_message.py`<br>`attacks.rsa.stereotyped_message` | `attack(N, e, c, partial_m, m=1, t=0)` | `stereotyped_message.attack(N, e, c, PartialInteger.lsb_of(m, 1024, 950), m=2)` |
| RSA | Wiener's attack | `attacks/rsa/wiener_attack.py`<br>`attacks.rsa.wiener_attack` | `attack(N, e)` | `wiener_attack.attack(N, e)` |
| RSA | Wiener's attack for Common Prime RSA | `attacks/rsa/wiener_attack_common_prime.py`<br>`attacks.rsa.wiener_attack_common_prime` | `attack(N, e, delta=0.25, m=1, t=None, check_bounds=True)` | `wiener_attack_common_prime.attack(N, e, delta, m=1, t=0)` |
| RSA | Wiener's attack (Heuristic lattice variant) | `attacks/rsa/wiener_attack_lattice.py`<br>`attacks.rsa.wiener_attack_lattice` | `attack(N, e)` | `wiener_attack_lattice.attack(N, e)` |
| Shamir's Secret Sharing | Deterministic coefficients | `attacks/shamir_secret_sharing/deterministic_coefficients.py`<br>`attacks.shamir_secret_sharing.deterministic_coefficients` | `attack(p, k, a1, f, x, y)` | `deterministic_coefficients.attack(p, k, a[1], f, xs[0], ys[0])` |
| Shamir's Secret Sharing | Share forgery | `attacks/shamir_secret_sharing/share_forgery.py`<br>`attacks.shamir_secret_sharing.share_forgery` | `attack(p, s, s_, x, y, xs)` | `share_forgery.attack(p, s, s_, xs[0], ys[0], xs[1:])` |
</details>

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

## Image size (reference)

On `linux/amd64`, `sage-ctf:10.8` is currently about **12.9GB** (`docker image ls`). This is mostly SageMath + its full dependency stack.

## Image vs container names

- Rename/tag the image (same bits, new name): `docker tag sage-ctf:10.8 yourname/sage-ctf:10.8`
- Create a container with a custom name: `docker run --name my-ctf --rm -it sage-ctf:10.8 bash`
- Rename an existing container: `docker rename old-name new-name`

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

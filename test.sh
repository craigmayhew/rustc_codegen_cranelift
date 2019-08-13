#!/bin/bash

set -e

if [[ "$1" == "--release" ]]; then
    export CHANNEL='release'
    cargo build --release $CG_CLIF_COMPILE_FLAGS
else
    export CHANNEL='debug'
    cargo build $CG_CLIF_COMPILE_FLAGS
fi

source config.sh

jit() {
    if [[ `uname` == 'Darwin' ]]; then
        # FIXME(#671) `dlsym` returns "symbol not found" for existing symbols on macOS.
        echo "[JIT] $1 (Ignored on macOS)"
    else
        echo "[JIT] $1"
        SHOULD_RUN=1 $RUSTC --crate-type bin -Cprefer-dynamic $2
    fi
}

rm -r target/out || true
mkdir -p target/out/clif

echo "[BUILD] mini_core"
$RUSTC example/mini_core.rs --crate-name mini_core --crate-type lib,dylib

echo "[BUILD] example"
$RUSTC example/example.rs --crate-type lib

JIT_ARGS="abc bcd" jit mini_core_hello_world example/mini_core_hello_world.rs

echo "[AOT] mini_core_hello_world"
$RUSTC example/mini_core_hello_world.rs --crate-name mini_core_hello_world --crate-type bin
./target/out/mini_core_hello_world abc bcd

echo "[AOT] arbitrary_self_types_pointers_and_wrappers"
$RUSTC example/arbitrary_self_types_pointers_and_wrappers.rs --crate-type bin -Cpanic=abort
./target/out/arbitrary_self_types_pointers_and_wrappers

echo "[BUILD] sysroot"
time ./build_sysroot/build_sysroot.sh

$RUSTC example/std_example.rs --crate-type bin
./target/out/std_example

git clone https://github.com/rust-lang/rust.git --depth=1 || true
cd rust
#git checkout -- .
#git pull
export RUSTFLAGS=

#git apply ../rust_lang.patch


rm config.toml || true

cat > config.toml <<EOF
[rust]
codegen-backends = []
[build]
local-rebuild = true
rustc = "$HOME/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/bin/rustc"
EOF

#rm -r src/test/ui/{asm-*,abi-*,extern/,panic-runtime/,panics/,unsized-locals/,proc-macro/,threads-sendsync/,thinlto/,simd*,borrowck/,variadic*,test*} || true
#rm src/test/ui/*lto*.rs || true
#for test in src/test/ui/*.rs src/test/ui/**/*.rs; do
#    if grep "ignore-emscripten" $test 2>&1 >/dev/null; then
#        rm $test
#    fi
#done
#rm src/test/ui/confuse-field-and-method/issue-2392.rs || true # Borrowck error difference
#rm src/test/ui/span/borrowck-call-is-borrow-issue-12224.rs || true # ^
#rm src/test/ui/consts/const-size_of-cycle.rs || true # Error file path difference
#rm src/test/ui/impl-trait/impl-generic-mismatch.rs || true # ^
#rm src/test/ui/type_length_limit.rs || true
#rm src/test/ui/huge-{array,array-simple-64,enum,struct}.rs || true # cg_clif doesn't provide a span for type is too big for arch
#rm src/test/ui/issues/issue-15919-64.rs || true # ^
#rm src/test/ui/issues/issue-23458.rs || true # Inline asm
#rm src.test/ui/lint/lint-ctypes-enum.rs || true # NonZeroU128 patched away
#rm src/test/ui/issues/issue-50993.rs || true # Target `thumbv7em-none-eabihf` is not supported

RUSTC_ARGS="-Zcodegen-backend="$(pwd)"/../target/"$CHANNEL"/librustc_codegen_cranelift."$dylib_ext" --sysroot "$(pwd)"/../build_sysroot/sysroot -Cpanic=abort"

echo "[TEST] rustc test suite"
./x.py test --stage 0 src/test/ui/ --rustc-args "$RUSTC_ARGS" 2>&1 | tee log.txt

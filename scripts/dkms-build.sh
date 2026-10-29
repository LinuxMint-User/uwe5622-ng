#!/bin/sh
# 由 DKMS 在 build 目录内调用（该目录无空格，可直接就地编译）。
# 用法：sh scripts/dkms-build.sh <内核构建树>
set -e

KSRC=${1:-/lib/modules/$(uname -r)/build}
BUILD=$(pwd)

# BUILDSRC 与 SRC 相同，Makefile 会跳过 rsync 就地编译，
# 产物仍落在各子目录，由 dkms.conf 的 BUILT_MODULE_LOCATION 指认。
make -C "$BUILD" KDIR="$KSRC" BUILDSRC="$BUILD" JOBS="$(nproc)"

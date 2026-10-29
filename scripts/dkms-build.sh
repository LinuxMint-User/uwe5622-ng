#!/bin/sh
# 由 DKMS 在 build 目录内调用（该目录无空格，可直接就地编译）。
# 用法：sh scripts/dkms-build.sh <内核构建树>
set -e

KSRC=${1:-/lib/modules/$(uname -r)/build}
BUILD=$(pwd)

# BUILDSRC 与 SRC 相同，Makefile 会跳过 rsync 就地编译，
# 产物仍落在各子目录，由 dkms.conf 的 BUILT_MODULE_LOCATION 指认。
# DKMS 在目标机上原生编译，CROSS_COMPILE 必须显式置空，
# 否则会沿用 Makefile 里为开发机交叉编译准备的 aarch64-linux-gnu- 前缀。
make -C "$BUILD" KDIR="$KSRC" BUILDSRC="$BUILD" ARCH=arm64 CROSS_COMPILE= \
	JOBS="$(nproc)"

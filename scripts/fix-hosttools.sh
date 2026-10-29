#!/bin/bash
# 精简构建树是在 x86 开发机上生成的，scripts/ 下的主机工具（fixdep、modpost、
# sign-file 等）是 x86 二进制，板上 aarch64 无法执行。删掉后让 kbuild 用板上
# gcc 重新编译。
#
# 用法：sudo ./fix-hosttools.sh [内核构建树路径]

set -euo pipefail

TREE=${1:-/usr/src/linux-$(uname -r)}
[ -d "$TREE" ] || { echo "没有这个目录：$TREE"; exit 2; }

echo "== 删除开发机编的 x86 主机工具 =="
for f in scripts/basic/fixdep scripts/basic/bin2c \
	 scripts/kconfig/conf scripts/kconfig/mconf scripts/kconfig/nconf \
	 scripts/mod/modpost scripts/mod/mk_elfconfig \
	 scripts/sign-file scripts/asn1_compiler; do
	if [ -e "$TREE/$f" ]; then
		rm -f "$TREE/$f"
		echo "  rm $f"
	fi
done

echo "== 用板上 gcc 重建 =="
make -C "$TREE" modules_prepare

echo "== 校验 =="
for f in scripts/basic/fixdep scripts/mod/modpost; do
	if [ -x "$TREE/$f" ]; then
		printf '%-24s %s\n' "$f" "$(file -b "$TREE/$f" 2>/dev/null || echo '(file 命令缺失)')"
	else
		echo "警告：$TREE/$f 仍不存在"
	fi
done

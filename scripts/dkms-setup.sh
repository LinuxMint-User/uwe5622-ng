#!/bin/bash
# 在板上（root）安装 DKMS 需要的两样东西，并把驱动注册进 DKMS。
#
# 用法：sudo ./dkms-setup.sh <内核构建树.tar.gz> <驱动源码.tar.gz>
# 例如：sudo ./dkms-setup.sh /tmp/linux-6.18.0-zero3.tar.gz /tmp/uwe5622-ng-6.18.0.tar.gz
#
# 做四件事：
#   1. 解出精简内核构建树到 /usr/src/linux-<ver>
#   2. 把 /lib/modules/<ver>/build 指向它（换掉板上那条悬空软链）
#   3. 解出驱动源码到 /usr/src/uwe5622-ng-<ver>（含 dkms.conf）
#   4. dkms add / build / install，装到 /lib/modules/<ver>/extra/uwe5622
# 不做 rmmod；重启后由启动流程加载新模块。

set -euo pipefail

KVER=$(uname -r)
TREE_TAR=${1:-}
SRC_TAR=${2:-}

[ "$(id -u)" -eq 0 ] || { echo "需要 root 运行"; exit 2; }
[ -f "$TREE_TAR" ] && [ -f "$SRC_TAR" ] || {
	echo "用法：$0 <内核构建树.tar.gz> <驱动源码.tar.gz>"; exit 2; }
command -v dkms >/dev/null || {
	echo "错误：没有 dkms，请先 pacman -S dkms"; exit 1; }

TREE=/usr/src/linux-$KVER
SRCDIR=/usr/src/uwe5622-ng-$KVER

echo "== 1. 内核构建树 -> $TREE =="
mkdir -p "$TREE"
tar xzf "$TREE_TAR" -C /usr/src
[ -f "$TREE/Makefile" ] || { echo "错误：$TREE/Makefile 不存在"; exit 1; }

echo "== 2. 修正 build 软链 =="
ln -sfn "$TREE" "/lib/modules/$KVER/build"
ls -l "/lib/modules/$KVER/build"

echo "== 3. 驱动源码 -> $SRCDIR =="
rm -rf "$SRCDIR"
mkdir -p "$SRCDIR"
tar xzf "$SRC_TAR" -C "$SRCDIR"
[ -f "$SRCDIR/dkms.conf" ] || { echo "错误：$SRCDIR/dkms.conf 不存在"; exit 1; }

echo "== 4. dkms add / build / install =="
dkms remove -m uwe5622-ng -v "$KVER" --all >/dev/null 2>&1 || true
dkms add "$SRCDIR"
dkms build -m uwe5622-ng -v "$KVER" -k "$KVER"
dkms install -m uwe5622-ng -v "$KVER" -k "$KVER" --force

echo "== 5. 结果 =="
for m in uwe5622_bsp_sdio sprdwl_ng sprdbt_tty sunxi_addr; do
	printf '%-22s %s\n' "$m" "$(modinfo -F filename "$m" 2>/dev/null || echo MISSING)"
done
ls -l "/lib/modules/$KVER/extra/uwe5622/"

echo
echo "完成。重启后验证：sudo $(dirname "$0")/smoke.sh"

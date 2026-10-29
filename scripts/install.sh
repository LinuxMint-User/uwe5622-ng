#!/bin/bash
# 安装 uwe5622 模块到 /usr/lib/modules/$(uname -r)/extra/uwe5622/
#
# 用法：sudo ./install.sh <目录>
#   <目录> 下（含子目录）需能找到四个 .ko：
#     uwe5622_bsp_sdio.ko  sprdwl_ng.ko  sprdbt_tty.ko  sunxi_addr.ko
#   本地编译树里它们分散在各子目录，直接传编译根目录即可；
#   也可以在板上建 /tmp/ko，把四个文件 scp 进去后传 /tmp/ko。
#
# 注意：本脚本不做 rmmod。sprdbt_tty 的卸载路径可能卡死整机（9.12），
#       装完统一重启生效，由启动时的 modprobe 加载新模块。

set -euo pipefail

SRC=${1:-}
MODS=(uwe5622_bsp_sdio sprdwl_ng sprdbt_tty sunxi_addr)
KVER=$(uname -r)
DEST=/usr/lib/modules/$KVER/extra/uwe5622

[ "$(id -u)" -eq 0 ] || { echo "需要 root 运行"; exit 2; }
[ -n "$SRC" ] && [ -d "$SRC" ] || { echo "用法：$0 <包含 .ko 的目录>"; exit 2; }

declare -A PATH_OF
for m in "${MODS[@]}"; do
	ko=$(find "$SRC" -maxdepth 3 -name "$m.ko" -print -quit)
	[ -n "$ko" ] || { echo "错误：$SRC 下找不到 $m.ko"; exit 1; }
	[ -s "$ko" ] || { echo "错误：$ko 是空文件（之前出现过写入中断）"; exit 1; }
	ver=$(modinfo -F vermagic "$ko" | awk '{print $1}')
	[ "$ver" = "$KVER" ] || {
		echo "错误：$m.ko 的 vermagic=$ver，当前内核是 $KVER"
		exit 1
	}
	PATH_OF[$m]=$ko
done

mkdir -p "$DEST"
for m in "${MODS[@]}"; do
	tmp="$DEST/.$m.ko.new"
	cp "${PATH_OF[$m]}" "$tmp"
	# 先写临时文件再原子替换，避免中断留下 0 字节模块
	mv -f "$tmp" "$DEST/$m.ko"
	echo "已安装 $m.ko  md5=$(md5sum "$DEST/$m.ko" | cut -c1-8)"
done

depmod -a "$KVER"
modinfo -F filename uwe5622_bsp_sdio sprdwl_ng sprdbt_tty sunxi_addr 2>/dev/null || true

echo
echo "完成。请重启后生效（本脚本故意不 rmmod）："
echo "  sudo reboot"
echo "起来后自检：sudo $(dirname "$0")/smoke.sh"

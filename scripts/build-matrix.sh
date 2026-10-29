#!/bin/bash
# 在多棵内核树上依次编译驱动，输出一张汇总表。
#
# 用法：
#   ./scripts/build-matrix.sh                      # 默认编 BUILDROOT 下的 6.18 与 7.2.13
#   ./scripts/build-matrix.sh /path/A /path/B       # 指定内核构建树
#
# 每棵树先 clean 再编，避免上一轮的产物混进来。
# 任一内核失败时退出码为 1，失败日志保留在 /tmp。

set -uo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
BUILDROOT=${BUILDROOT:-$HOME/.cache/uwe5622-build}
BUILDSRC="$BUILDROOT/src/uwe5622-ng"

kernels=("$@")
if [ ${#kernels[@]} -eq 0 ]; then
	kernels=("$BUILDROOT/linux-6.18-zero3-src" "$BUILDROOT/linux-7.2.13")
fi

# 模块名:所在子目录
mods=(
	"uwe5622_bsp_sdio:unisocwcn"
	"sprdwl_ng:unisocwifi"
	"sprdbt_tty:tty-sdio"
	"sunxi_addr:addr_mgt"
)

logdir=$(mktemp -d)
trap 'rm -rf "$logdir"' EXIT

rows=()
failed=0
i=0

for kdir in "${kernels[@]}"; do
	i=$((i + 1))
	name=$(basename "$kdir")

	if [ ! -f "$kdir/Makefile" ] || [ ! -f "$kdir/include/config/auto.conf" ]; then
		printf '[%d/%d] %-26s SKIP（不是已 prepare 的内核构建树）\n' \
			"$i" "${#kernels[@]}" "$name"
		rows+=("$name|SKIP|-|-|-|-")
		continue
	fi

	printf '[%d/%d] %-26s 编译中...\n' "$i" "${#kernels[@]}" "$name"
	make -C "$repo" KDIR="$kdir" clean >/dev/null 2>&1

	log="$logdir/$name.log"
	if make -C "$repo" KDIR="$kdir" >"$log" 2>&1; then
		status=PASS
	else
		status=FAIL
		failed=1
		keep="/tmp/uwe5622-matrix-$name.log"
		cp "$log" "$keep"
		printf '        失败，日志见 %s\n' "$keep"
	fi

	row="$name|$status"
	for m in "${mods[@]}"; do
		mod=${m%%:*}
		sub=${m##*:}
		ko="$BUILDSRC/$sub/$mod.ko"
		if [ -s "$ko" ]; then
			size=$(du -h "$ko" | cut -f1)
			ver=$(modinfo -F vermagic "$ko" 2>/dev/null | awk '{print $1}')
			row="$row|$size/$ver"
		else
			row="$row|-"
		fi
	done
	rows+=("$row")
done

echo
# 表头按显示宽度对齐：中文占两列，"内核树"=6 列、"结果"=4 列，
# 所以宽度分别给 23 和 3 才能和下面 %-26s / %-5s 的数据行对齐。
printf '%-23s %-3s %-21s %-21s %-21s %-21s\n' \
	"内核树" "结果" "${mods[0]%%:*}" "${mods[1]%%:*}" "${mods[2]%%:*}" "${mods[3]%%:*}"
for row in "${rows[@]}"; do
	IFS='|' read -r -a f <<<"$row"
	printf '%-26s %-5s %-21s %-21s %-21s %-21s\n' \
		"${f[0]}" "${f[1]}" "${f[2]}" "${f[3]}" "${f[4]}" "${f[5]}"
done

exit "$failed"

#!/bin/bash
# uwe5622 冒烟自检：模块 / WiFi / 蓝牙 / 内核日志
# 用法：sudo ./smoke.sh
# 退出码：0 全部通过，1 有失败项，2 用法或权限错误

set -u

FAIL=0
pass() { printf 'PASS  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=1; }

[ "$(id -u)" -eq 0 ] || { echo "需要 root 运行"; exit 2; }

echo "== 1. 模块 =="
for m in uwe5622_bsp_sdio sprdwl_ng sprdbt_tty sunxi_addr; do
	if grep -q "^$m " /proc/modules; then
		pass "$m 已加载"
	elif modprobe "$m" 2>/dev/null && grep -q "^$m " /proc/modules; then
		pass "$m 已加载（本次 modprobe）"
	else
		bad "$m 未加载"
	fi
done

echo "== 2. WiFi =="
if [ -e /sys/class/net/wlan0 ]; then
	pass "wlan0 存在"
	rfkill unblock wifi 2>/dev/null
	ip link set wlan0 up 2>/dev/null
	sleep 2
	AP=$(iw dev wlan0 scan 2>/dev/null | grep -c '^BSS')
	if [ "$AP" -ge 1 ]; then
		pass "扫描到 $AP 个 BSS"
	else
		bad "扫描不到任何 AP"
	fi
else
	bad "wlan0 不存在（固件下载或 SDIO 枚举失败？）"
fi

echo "== 3. 蓝牙 =="
if [ -e /sys/class/bluetooth/hci0 ]; then
	pass "hci0 存在"
	INFO=$(btmgmt info 2>/dev/null)
	if echo "$INFO" | grep -q 'powered'; then
		pass "hci0 powered"
	else
		bad "hci0 未 powered"
	fi
	DEV=$(timeout 20 btmgmt find 2>/dev/null | grep -c 'dev_found')
	if [ "$DEV" -ge 1 ]; then
		pass "inquiry 发现 $DEV 个设备"
	else
		bad "inquiry 没有发现任何设备"
	fi
else
	bad "hci0 不存在（hciattach_opi 没在跑？）"
fi

echo "== 4. 内核日志 =="
OOPS=$(dmesg | grep -cE 'Oops|WARNING: CPU|BUG: ')
TX=$(dmesg | grep -c 'tx timeout')
[ "$OOPS" -eq 0 ] && pass "无 Oops / WARNING / BUG" || bad "发现 $OOPS 条 Oops/WARNING/BUG"
[ "$TX" -eq 0 ] && pass "无 HCI tx timeout" || bad "发现 $TX 条 tx timeout"

echo
if [ "$FAIL" -eq 0 ]; then
	echo "结果：全部通过"
else
	echo "结果：有失败项（详见上面 FAIL 行，配合 dmesg 排查）"
fi
exit "$FAIL"

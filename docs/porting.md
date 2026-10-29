# 移植到新内核

把驱动从当前已验证的版本（`6.18.0` / `7.2.13`）迁移到更新的主线内核时，按下面顺序执行。
每步都有明确的"完成判据"，不要跳步。

## 0. 先留退路

- 旧内核的 `Image`、dtb、`/lib/modules/<旧版本>` 全部保留。
- 改 `extlinux.conf` 之前先备份：`cp extlinux.conf extlinux.conf.bak`。

## 1. 扫描 API 断点

```sh
git -C linux-new log --oneline <旧版本tag>..<新版本tag> \
    -- include/net/cfg80211.h net/mac80211.h include/linux/netdevice.h
git -C linux-new diff <旧版本tag>..<新版本tag> -- include/net/cfg80211.h | grep -E '^[-+].*(struct|void|int)'
```

重点看这几类：

| 位置 | 看什么 |
|---|---|
| `struct cfg80211_ops` | 成员是否改名、回调签名是否变化 |
| `struct net_device_ops` | 同上 |
| `struct file_operations` | `.read` / `.write` 是否变成 `.read_iter` 等 |
| `platform_driver` / `class_create` | `.remove` 返回值、参数个数 |
| `str*` 系列 | 是否已从内核中删除（如 `strncpy`） |

本项目在 `6.18 → 7.2` 之间实际遇到的断点，已全部收进 `compat.h`，可作为参考：
`class_create(THIS_MODULE, ...)` 去掉 owner、`platform_driver.remove` 改为 `void`、
`change_beacon` → `cfg80211_ap_update`、`tdls_mgmt` 增加 `link_id`、
`change_station` / `delete_station` 改用 `wireless_dev *`、`remain_on_channel` 参数变化、
`strncpy` 与 `linux/of_gpio.h` 被移除。

## 2. 准备内核树

```sh
zcat /proc/config.gz > .config        # 或沿用旧内核的 .config
make olddefconfig
make modules_prepare
```

判据：`include/config/auto.conf` 与 `include/generated/autoconf.h` 存在。

**注意**：外部模块编译只需要这两份配置产物；`modules_prepare` 是树内目标，会触发 syncconfig，
需要 Kconfig、`scripts/dtc`、`tools/include` 等完整目录。精简树（只留头文件）在板上编不过。

## 3. 编译矩阵

```sh
./scripts/build-matrix.sh <新内核树> <旧内核树>
```

判据：两棵树都 PASS，且 vermagic 分别对应各自版本。

## 4. 生成 headers 树（目标机上做）

```sh
make -C <内核源码树> modules_prepare
make -C <内核源码树> INSTALL_HDR_PATH=<目标路径> headers_install   # 如需 UAPI
sh <内核源码树>/scripts/package/install-extmod-build <输出目录>
```

必须在**目标机**上生成：`fixdep`、`modpost` 是主机工具，交叉工具链编不出来。
开发机上生成的树只能给开发机自己用。

## 5. 重建 DKMS

```sh
sudo dkms build   -m uwe5622-ng -v <内核版本> -k <内核版本>
sudo dkms install -m uwe5622-ng -v <内核版本> -k <内核版本> --force
```

判据：`dkms status` 显示 `installed`，四个 `.ko` 非空，vermagic 与新内核一致。

## 6. depmod 必须真正跑完

```sh
sudo depmod -a <内核版本> && ls -l /lib/modules/<内核版本>/modules.dep
```

**这一步失败不要重启。** 曾经的故障链是：

```
depmod 被 I/O 错误打断 → modules.dep 未生成
→ /boot（vfat）挂载时找不到 nls_iso8859-1 模块
→ Failed to mount /boot → Emergency Mode → SSH 不再启动
```

## 7. 确认 /boot 依赖的模块齐全

```sh
grep -E 'CONFIG_NLS_(ISO8859_1|UTF8|CODEPAGE_437)' /boot/config-<版本>
```

这些是 `=m` 时要确认 modules.dep 能解析到；否则挂 `/boot` 会失败。

## 8. 设备树补丁重新套用

这一步需要**完整内核源码树**（第 4 步那棵 headers 树只能编模块，编不了 dtb），
补丁的路径前缀是 `arch/arm64/boot/dts/allwinner/`，所以在源码树根目录 `-p1` 即可：

```sh
cd <内核源码树>
patch -p1 --dry-run < /path/to/zero3-dt.patch
```

补丁见 [orangepi-zero-3-dtb-neo](https://github.com/LinuxMint-User/orangepi-zero-3-dtb-neo) 的
`patches/zero3-dt.patch`。只想编 dtb 的话，也可以直接用同仓库展开好的
`sun50i-h618-orangepi-zero3-neo.dts`，不需要主线源码树。

判据：只有 `checking file ...`，没有 fuzz 或失败。
若上游改了同一位置，按新结构手工合并，不要用 `--force` 硬打。

打完确认能编出来：

```sh
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     allwinner/sun50i-h618-orangepi-zero3.dtb
```

## 9. 固件与蓝牙 ini

- 固件包升级可能覆盖 `/lib/firmware/bt_configure_pskey.ini`。
- 确认 `feature_set` 的第二个字节是 `0xFE`，否则 `hci0` 会停在 `HCI_SETUP`。

## 10. 冷启动验收

重启后**不要手动 modprobe**，直接：

```sh
sudo ./scripts/smoke.sh
```

判据：四项全 PASS（模块自动加载、WiFi 扫描、蓝牙 powered + inquiry、无 Oops / tx timeout）。

---

## 常见故障对照

| 现象 | 原因 |
|---|---|
| `insmod: Exec format error` / `this_module section size must match` | 用了 config 不一致的内核树编译（如缺 `CONFIG_MODULE_SIG`） |
| `modinfo` 的 vermagic 与 `uname -r` 不符 | 同上，或装错了目录 |
| 开机进 Emergency，`Failed to mount /boot` | `depmod` 未完成，`nls_iso8859-1` 找不到 |
| `hci0` 停在 `HCI_SETUP`，`btmgmt` 显示 0 个控制器 | 蓝牙 ini 被覆盖，park 位重新上报 |
| 网口指示灯不亮 | 设备树缺 PHY `leds` 子节点 |
| 所有命令报"无法执行：找不到需要的文件" | `/lib` 软链接被解包破坏（往 `/` 解包了带 `lib/` 顶层的归档） |

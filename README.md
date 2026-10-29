# uwe5622-ng

Unisoc（展锐）UWE5622 / AW859A 无线芯片的 WiFi + 蓝牙驱动，**树外（out-of-tree）构建**，面向主线内核。

当前主要在 Orange Pi Zero 3（Allwinner H618，SDIO 接法）上验证，四个模块：

| 模块 | 作用 |
|---|---|
| `uwe5622_bsp_sdio` | SDIO 传输层与固件下载（marlin3） |
| `sprdwl_ng` | WiFi（cfg80211） |
| `sprdbt_tty` | 蓝牙 H4 传输 |
| `sunxi_addr` | MAC 地址管理（原 `sunxi-addr`） |

## 状态

| 内核 | 结果 |
|---|---|
| `7.2.13` | 编译、加载、WiFi 扫描、蓝牙 inquiry 全部通过 |
| `6.18.0`（LTS） | 同上 |

- **零内核补丁**：全部为树外模块，不修改内核源码，也不需要重新编译内核镜像。
- 与内核的 API 差异全部集中在 `compat.h`，业务代码里不出现版本判断。
- 平台差异集中在 `unisocwcn/platform/`，其余代码不依赖具体板子。

## 依赖

1. **内核 headers 树**：`/lib/modules/$(uname -r)/build` 可用（发行版式 headers 即可，不需要完整源码树）。
2. **设备树**：需要板级节点（WiFi 供电与 pwrseq、`addr-mgt` 等），见
   [orangepi-zero-3-dtb-neo](https://github.com/LinuxMint-User/orangepi-zero-3-dtb-neo)。
3. **固件**：`/lib/firmware/wcnmodem.bin` 等，Arch Linux ARM 上由 `uwe5622-firmware` 提供。
4. **蓝牙一项配置**：`/lib/firmware/bt_configure_pskey.ini` 里 `feature_set` 的第 2 个字节改成 `0xFE`。
   不改的话，芯片会上报 park 能力，`Write_Default_Link_Policy` 返回 `0x12`，`hci_init3` 中止，
   `hci0` 停在 `HCI_SETUP`。改 ini 即可，不需要内核补丁。

蓝牙由 `hciattach_opi` 拉起：

```sh
hciattach_opi -n -s 1500000 /dev/ttyBT0 sprd &
```

## 构建

### 交叉编译（开发机）

```sh
make KDIR=/path/to/linux-7.2.13 \
     ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
```

产物（`.ko`）落在各模块子目录下。`BUILDROOT` / `BUILDSRC` 可覆盖：Kbuild 不接受含空格的模块路径，
顶层 Makefile 会先把源码镜像到无空格的 `BUILDSRC` 再编译。

### 编译矩阵

一次编多个内核版本，用于确认 `compat.h` 的改动没有在某个版本上回归：

```sh
./scripts/build-matrix.sh                       # 默认编 BUILDROOT 下的 6.18 与 7.2.13
./scripts/build-matrix.sh /path/A /path/B       # 指定内核构建树
```

每棵树先 `clean` 再编，最后输出 PASS/FAIL 与各模块的大小和 vermagic；任一失败时退出码为 1，
失败日志留在 `/tmp/uwe5622-matrix-<内核树名>.log`。

### 原生编译（目标机，DKMS）

```sh
sudo ./scripts/dkms-setup.sh /path/to/linux-7.2.13.tar.xz /path/to/uwe5622-ng.tar.gz
```

脚本会解出内核源码、`olddefconfig` + `modules_prepare`、修正 `build` 软链、解出驱动源码，
然后 `dkms add/build/install`。已经注册过 DKMS 时可以直接：

```sh
sudo dkms build   -m uwe5622-ng -v 7.2.13 -k 7.2.13
sudo dkms install -m uwe5622-ng -v 7.2.13 -k 7.2.13 --force
sudo depmod -a 7.2.13
```

## 部署与验证

```sh
sudo ./scripts/install.sh   # 校验 vermagic 与文件非空、原子替换、depmod
sudo ./scripts/smoke.sh     # 模块 / WiFi 扫描 / 蓝牙 / dmesg 检查
```

`smoke.sh` 输出 PASS/FAIL，四项全 PASS 视为通过。

## 目录

```
compat.h         版本差异的唯一入口
Makefile         树外构建入口（多个模块目录分别编译）
Kconfig          模块内配置项
dkms.conf        DKMS 描述
unisocwcn/       核心、SDIO 传输、固件下载（platform/ 在此目录内）
unisocwifi/      WiFi
tty-sdio/        蓝牙传输
addr_mgt/        MAC 地址管理
scripts/         构建、部署、验证脚本
```

## 已知限制

- 只实测过 SDIO 路径。PCIe / USB / GNSS 相关代码保留在树内，默认不参与构建。
- 只在 Orange Pi Zero 3 + `6.18.0` / `7.2.13` 上验证过，其他板子与其他内核版本需要自行确认。
- 仍依赖闭源固件（`wcnmodem.bin` 等），不在本仓库内分发。

## 许可

GPL-2.0，见 [LICENSE](LICENSE)。代码源自 Allwinner / Unisoc 的厂商驱动，与内核模块接口一致。

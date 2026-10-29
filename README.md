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
- 新内核的 API 差异优先收进 `compat.h`（用类型别名抹平签名，而不是按版本复制整个函数）；
  厂商遗留的旧版本判断仍散落在业务代码里，暂未清理。
- 平台差异集中在 `unisocwcn/platform/`，其余代码不依赖具体板子。

## 与 Armbian 版本的区别

Armbian 也在维护同一份驱动：[armbian/uwe5622](https://github.com/armbian/uwe5622)。两者同源
（他们从 `uwe5622-allwinner-v6.3.patch` 起步，本仓库从 Orange Pi 的 6.1 厂商树起步），
213 个文件里 119 个逐字节相同，实质差异约 3.7k 行（占 1.8%）。区别在工程取向，不在驱动功能：

| | Armbian | 本仓库 |
|---|---|---|
| 重心 | 覆盖面：Armbian 构建系统内的多块板，Allwinner + Rockchip，6.1 ~ 7.3 | 深度：单板实测，`6.18.0` / `7.2.13` |
| 验证方式 | CI 只编译 | 上板跑 WiFi 关联、蓝牙 inquiry、冷启动 |
| 7.x API 适配 | 按版本复制整个函数（`#if` 分叉） | `compat.h` 用类型别名抹平签名，函数只写一份 |
| `KERNEL_VERSION` 判断 | 312 处 | 214 处（含尚未清理的厂商遗留） |
| MAC 地址 | 无 `addr_mgt` 等价物 | `addr_mgt/` 从 DT `serial-number` 派生，每板唯一 |
| 固件加载 | 保留 `filp_open`，额外加 `wcn_fs.h` 处理 7.3 kthread 根目录变化 | 改用 `request_firmware()` |
| 蓝牙 park-link | 只有存档的内核补丁，当前树未应用 | 零内核补丁，改 ini 一个字节 |
| DKMS | `CLEAN=` 已弃用；只装 3 个模块 | 4 个模块全装，`MAKE[0]` 显式置空 `CROSS_COMPILE` |
| 固件目录 | `/lib/firmware/uwe5622/` 优先 | `/lib/firmware/` |

怎么选：

- 在 Armbian 发行版内用、需要 Rockchip 板、或者要更老/更新的内核 → 用 Armbian 那份。
- 自己的发行版、需要 MAC 管理、需要零内核补丁、要在 7.2.13 上有实测证据 → 用本仓库。

两边面向的系统不同，会各自继续演进，不计划合并。

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
docs/            文档（移植到新内核的检查清单）
```

## 移植到新内核

升级到更新的主线内核时，按 [docs/porting.md](docs/porting.md) 的清单逐项执行。

## 已知限制

- 只实测过 SDIO 路径。PCIe / USB / GNSS 相关代码保留在树内，默认不参与构建。
- 只在 Orange Pi Zero 3 + `6.18.0` / `7.2.13` 上验证过，其他板子与其他内核版本需要自行确认。
- 仍依赖闭源固件（`wcnmodem.bin` 等），不在本仓库内分发。

## 许可

GPL-2.0，见 [LICENSE](LICENSE)。代码源自 Allwinner / Unisoc 的厂商驱动，与内核模块接口一致。

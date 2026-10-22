# 当贝 B3 Pro 安装 Armbian

适用：4 GB 当贝 B3 Pro。实测镜像：`Armbian_26.11.0_amlogic_s922x_trixie_6.12.112_server_2026.10.15`。本包不含系统镜像，刷写前请确认所选盘可以清空；有条件时另留一只可启动 U 盘作恢复盘。

## 1. 制作 USB 启动盘

从 [ophub Armbian Releases](https://github.com/ophub/amlogic-s9xxx-armbian/releases) 获取上述镜像，用 balenaEtcher 或 Rufus 写入 U 盘或 USB 固态盘。写入会清空目标盘。

解压本包，**打开 `B3Pro-Armbian-Setup-aionui` 文件夹，全选里面的内容，粘贴到新盘的 BOOT 分区根目录**。不要把最外层文件夹一起复制。遇到已有 `dtb` 文件夹时选“合并”，保留镜像原有的其他设备树。

```text
BOOT/
├── aml_autoscript
├── u-boot.ext
├── B3Pro/
│   ├── install.sh
│   ├── boot-emmc-direct-go.cmd
│   ├── boot-usb-first.cmd
│   └── ir/dangbei-b3-pro.toml
├── dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb
├── uEnv.txt                         ← 镜像原有文件
└── 其他镜像原有文件
```

编辑新盘原有的 `BOOT/uEnv.txt`，把 `FDT=` 一行改为：

```text
FDT=/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb
```

保留 `LINUX`、`INITRD` 和 `APPEND` 中的 **`root=` 原值**。不要复制别的盘的 `uEnv.txt`，否则 `root=` 可能指向错误分区。如果 `APPEND=` 行没有 `rootwait`，在行末加 ` rootwait`。电脑上不需要运行任何脚本。

USB 固态盘若使用 `174c:55aa` 转接器并出现 UAS 报错，可在同一行末尾尝试加 ` usb-storage.quirks=174c:55aa:u`，重启后确认是否生效。其他转接器不要照抄这个 ID；具体报错处理见文末。

## 2. 从 USB 启动盒子

插入做好的盘，给盒子通电，完成 Armbian 首次登录设置。确认显示器出现登录界面，且网络、USB 盘工作正常。登录后可先看根分区：

```bash
findmnt -no SOURCE /
findmnt -no SOURCE /boot
```

两行应来自同一只 USB 盘，例如 `sda2` 和 `sda1`。若进入 BusyBox、出现 `Input/output error`，或显示的是 eMMC 分区，**不要继续安装到 eMMC**，先检查 USB 盘和 `uEnv.txt`。

## 3. 运行安装脚本

在 USB 系统的 root 终端或 SSH 中运行：

```bash
bash /boot/B3Pro/install.sh
```

脚本会核对型号、文件、USB 根分区及 `uEnv.txt`，然后依次询问。想得到本教程的完整启动效果，请这样选择：

| 脚本问题 | 建议回答 |
| --- | --- |
| 启用 eMMC 冷启动直接显示？ | `y` |
| 安装红外支持？ | 按需 `y`，也可回车跳过 |
| 安装蓝牙支持？ | 按需 `y`，也可回车跳过 |
| 启用并连接 Wi-Fi？ | 按需 `y`，也可回车跳过 |
| 安装 eMMC 后启用 USB 优先启动？ | `y` |
| 现在运行 `armbian-install` 写入 eMMC？ | 确认目标盘后输入 `y` |

选择 Wi-Fi 后，脚本会开启无线电、显示附近网络，并让你输入 SSID；需要密码时由 NetworkManager 在终端询问。SSID 留空表示只开启 Wi-Fi，不建立连接。成功建立的连接配置会随 USB 系统一起复制到 eMMC。若当前没有 `nmcli` 或 Wi-Fi 接口，脚本会提示并跳过，不会阻止 eMMC 安装；可在 eMMC 启动后补设。密码不在本包中。

Wi-Fi、红外、蓝牙可以按 `Ctrl+C` 中断当前安装项，脚本会继续后面的步骤；以后可在 eMMC 系统重新运行同一脚本补装。刷写 eMMC 前，脚本不会为红外或蓝牙联网安装软件包。Wi-Fi 的板级配置在本包设备树中，固件由镜像提供。

脚本先只读检查 USB 系统的 `/usr` 和 eMMC 容量，然后调用 `armbian-install -m no -a yes`。安装器中选择 **`0 / Other Customize`**，按实测机填写：

| 安装器提示 | 填写 |
| --- | --- |
| SoC Name | `s922x` |
| DTB Name | `meson-g12b-dangbei-b3-pro.dtb` |
| UBOOT_OVERLOAD Name | `u-boot.ext` |
| MAINLINE_UBOOT Name | 留空 |
| BOOTLOADER_IMG Name | 留空 |
| 文件系统 | `1` / ext4 |

**确认安装目标是盒子的 eMMC。** `armbian-install` 会把当前 USB 系统复制进去，包括已设置的账号、密码、网络配置和首次登录状态。eMMC 重新分区后不一定再次要求设置密码。

安装器返回成功后，`install.sh` 还会核对 eMMC 根分区的关键文件、`/usr` 文件数量、BOOT 文件、`root=` 和设备树；缺少 `rootwait` 时会补上。选择 USB 优先时，它更新 eMMC 的 `boot.cmd`、`boot.scr`。选择直显时，它把已验证的 U-Boot 放在 eMMC BOOT 的 `u-boot.emmc`，更新 `emmc_autoscript` 使冷启动直接加载它。底层原厂引导器不会被刷写。

**必须等脚本明确显示 `eMMC 安装已结束`。** 若安装器报错、中断或脚本报告存储错误，不要拔盘尝试从 eMMC 启动；保留报错并先检查 USB 盘、转接器和供电。

## 4. 关机并逐项验证

成功后在盒子上执行 `poweroff`，等关机完成再进行以下测试。每次更换 USB 盘都先断电。

| 测试 | 预期结果 | 登录后检查 |
| --- | --- | --- |
| 拔掉 USB，再通电 | eMMC 直接显示 Armbian 登录界面 | `/` 来自 `mmcblk…p2` |
| 保持无 USB，再做一次断电冷启动 | 仍直接显示登录界面 | `/` 仍来自 eMMC |
| 断电后插回可启动 USB，再通电 | 进入 USB 系统 | `/` 来自 `sd…2` |
| 断电后插入没有 Armbian 启动文件的 USB 盘 | 回退 eMMC | `/` 来自 `mmcblk…p2` |

检查命令：

```bash
findmnt -no SOURCE /
findmnt -no SOURCE /boot
awk '/^MemTotal:/ {print $2 " kB"}' /proc/meminfo
```

这台实测 B3 Pro 识别约 `3896768 kB` 内存。若 USB 有 `uEnv.txt` 等启动文件、但根文件系统损坏，引导器无法提前判定它不能启动；拔掉该盘后再从 eMMC 启动。

## 可选功能以后补装

若刷机时跳过 Wi-Fi、红外或蓝牙，在 eMMC 系统确认 `/` 和 `/boot` 都来自 eMMC 后，可重新运行 `bash /boot/B3Pro/install.sh`，只选择要补装的项目，其他问题回车跳过。若 eMMC 的 `/boot/B3Pro` 不存在，先把本包的 `B3Pro` 文件夹、`u-boot.ext` 和设备树按第 1 步对应路径复制到 eMMC 的 `/boot`。脚本识别为 eMMC 系统时不会再运行 `armbian-install`。

Wi-Fi 设置完成后，可用 `nmcli device status` 查看 `wlan0` 是否已连接，再用 `ip -4 addr show wlan0` 检查是否取得地址。若只开启了无线电但没有填写 SSID，此时没有 IP 是正常的。

## 启动方案与限制

本包仅适用于上述实测机型和镜像。盒子先运行原有底层引导器，再从 eMMC BOOT 加载 `u-boot.emmc`；这份 U-Boot 按所选启动顺序加载 USB 或 eMMC。加载不到 `u-boot.emmc` 时，脚本会尝试原厂 eMMC 引导；若 U-Boot 自身卡住，无法保证自动回退。请保留恢复盘。

## 固态写入报错解决方法

若安装时出现大量 `tar: ... Input/output error`，立即停止安装并保留救援 U 盘。此类错误表示读取或写入失败，需要检查 USB 盘、转接器、供电、eMMC 和报错时的内核日志。安装中断后的 eMMC 可能已经被格式化，不能假定它仍可启动。

若使用 USB 固态盘，开机日志出现 `uas_eh_abort_handler`、`uas_eh_device_reset_handler` 或 `reset SuperSpeed USB device`，先查 USB 转接器的厂商/产品 ID。实测一只 Ugreen/ASMedia 转接器为 `174c:55aa`；可尝试在**这只盘**的 `BOOT/uEnv.txt` 的 `APPEND=` 行末增加 ` usb-storage.quirks=174c:55aa:u`。其他转接器不能照抄这个 ID。重启后用 `lsusb -t` 确认驱动是否变为 `usb-storage`，并检查内核日志不再报 USB 重置，再考虑写入 eMMC。Linux [内核参数文档](https://www.kernel.org/doc/html/next/admin-guide/kernel-parameters.html)将 `u` 定义为禁用 UAS 绑定。

## 其他硬件实测

- **Wi-Fi：** SDIO 25 MHz、4 位总线；曾在 5 GHz、5260 MHz 网络上取得 DHCP 地址，`wlan0` 访问公网测试 4/4 成功，重启后自动连接。那次测试的信号约为 −50 dBm。
- **蓝牙：** GPIOX_17 为 shutdown、GPIOX_19 为 device-wakeup，PWM_E / GPIOX_16 提供 LPO；固件 `BCM4356A2.hcd` 曾从 build 0000 更新至 0266。已验证扫描、与 Mac 配对，重启后配对状态保留。
- **红外：** NECX 前缀 `0x8102`；方向、返回、主页、菜单、音量和确定键均有事件，重启后 udev 能自动加载键表。
- **以太网：** 实际通信正常；没有拿到确认千兆速率的输出，不把千兆吞吐列为实测。
- **尚未验证：** 音频、GPU、视频硬解。

以上是同一台设备此前的测试记录，不能保证不同镜像、转接器或外设组合得到相同结果。

## 文件来源与发布说明

本包只放启动文件、设备树、红外键表和必要的安装脚本，不包含个人 Wi-Fi 密码、蓝牙配对信息或诊断日志。运行脚本后输入的 Wi-Fi 密码会保存在用户自己的系统连接配置中，不会写回发布包。

设备树基础和引导工作参考 [yefx/build-u-boot-dangbei-b3-pro](https://github.com/yefx/build-u-boot-dangbei-b3-pro)，并结合原厂设备树提取和这台机器的实测修正。内核、DTS 和 U-Boot 等组件遵循各自上游许可；本包不是完整的上游源码发布。

包内 `u-boot.ext` 是此前本地构建、在设备上验证的 U-Boot 2026.01 组件。对应的完整构建树、配置和第三方许可材料尚未收齐，**公开再分发此二进制前应补齐对应源码与许可材料**；不要把本包视为已经完成开源发布合规审查。

## 参考资料

[ophub 文档](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/documents/README.cn.md)、[yefx B3 Pro 项目](https://github.com/yefx/build-u-boot-dangbei-b3-pro)、[unifreq U-Boot](https://github.com/unifreq/u-boot)、[Amlogic 蓝牙参考驱动](https://github.com/hardkernel/linux/blob/odroidg12-4.9.y/drivers/amlogic/bluetooth/bt_device.c)。

# 当贝B3Pro刷armbian教程

适用：4+64GB 当贝 B3 Pro；实测 ophub Armbian 26.11 / Debian trixie / server / 内核 `6.12.112-ophub`。本包不含系统镜像。


## U盘系统

## 1. 写系统镜像

从 [ophub Armbian Releases](https://github.com/ophub/amlogic-s9xxx-armbian/releases) 下载 **amlogic / s922x / trixie / server** 镜像，我测试的内核 6.12.112-ophub。用 balenaEtcher 或 Rufus 写到 U 盘；会清空 U 盘。

下载`B3Pro-Armbian-Setup` 

打开解压后的 **`B3Pro-Armbian-Setup` 文件夹**，**全选里面的内容**，粘贴到 U 盘的 **BOOT 分区根目录**。

不要把最外层 `B3Pro-Armbian-Setup` 文件夹本身复制进去。若文件管理器询问如何处理已有的 `dtb` 文件夹，务必选**合并**，不能选整夹替换；如果没有“合并”选项，就单独把本包的 DTB 文件复制进现有的 `BOOT/dtb/amlogic/`。粘贴后应看到：

```text
BOOT/
├── aml_autoscript
├── u-boot.ext
├── B3Pro/
│   ├── install.sh
│   ├── ir/
│   └── 显示服务文件
├── dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb
├── uEnv.txt                 ← 镜像原有文件，不要覆盖
└── 其他镜像原有文件
```

**修改 uEnv.txt 文件**


只改原有 **`BOOT/uEnv.txt` 的一行**，把 `FDT=` 改成：

```text
FDT=/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb
```

保留原来的 `LINUX`、`INITRD` 和 `APPEND` 中的 `root=`。如果 `APPEND` 没有 `rootwait`，在该行末尾加一个空格和 `rootwait`。不同镜像的根分区参数可能不同，所以本包不提供可直接覆盖的通用 `uEnv.txt`。

## 2. 从 U 盘启动

安全弹出 U 盘，插入盒子，从 U 盘进入 Armbian。首次外部启动可能需要使用恢复键。建议先接网线。

进入ssh，默认root，密码1234

## 3. 写入 eMMC 系统

### 3.1 准备工作

### 注意：本固件不执行下方脚本刷入eMMC后无 HDMI 画面

想让 eMMC 系统有 HDMI 画面，在盒子的 root 终端或 SSH 中运行：

```bash
bash /boot/B3Pro/install.sh
```

这条命令把 HDMI 显示服务放进系统，并把设备树放到安装器需要的 `dtb/amlogic` 目录；还会安装红外键表，尝试安装 BlueZ。**Wi-Fi、蓝牙的板级配置在本包设备树中；无线固件使用实测镜像自带的文件。**

### 3.2 安装到 eMMC

尚未安装 eMMC 时，在当前 U 盘系统运行：

```bash
armbian-install
```

实测机选择 **0 / Other Customize**，依次填写：

| 提示 | 填写 |
| --- | --- |
| SoC Name | `s922x` |
| DTB Name | `meson-g12b-dangbei-b3-pro.dtb` |
| UBOOT_OVERLOAD Name | `u-boot.ext` |
| MAINLINE_UBOOT Name | 留空 |
| BOOTLOADER_IMG Name | 留空 |
| 文件系统 | `1` / ext4 |

确认安装目标确实是盒子的 eMMC 后再继续。如果**不想安装 HDMI 显示服务**，可跳过第 3.1 步的脚本，直接运行安装器；设备树已在标准路径。

安装完成后运行 `poweroff`。等盒子完全关机，拔掉 U 盘再通电。启用了显示服务的实测机先黑屏，**自动重启一次**后出现 Armbian 登录界面；这是热重启绕行方案，不是一次冷启动的底层修复。

## 已经装好 eMMC 系统，后来才想加HDMI显示

先用可显示的 U 盘引导，确认当前 `/` 和 `/boot` **实际来自 eMMC**，或者在黑屏但可 SSH 登录的 eMMC 系统中操作：

```bash
findmnt -no SOURCE /
findmnt -no SOURCE /boot
```

在电脑上把本包里的 **`B3Pro` 文件夹和 `u-boot.ext` 文件**传到盒子的 eMMC `/boot`。例如在解压后的 `B3Pro-Armbian-Setup` 目录运行（IP 改成自己的）：

```bash
scp -r B3Pro u-boot.ext root@盒子IP:/boot/
```

然后在盒子的 root 终端运行：

```bash
bash /boot/B3Pro/install.sh
poweroff
```

关机后拔掉 U 盘，再通电。**不需要重装 eMMC。** 如果 `findmnt` 显示根分区来自 U 盘，先停止；否则文件会装到 U 盘系统里。已经装好的 eMMC 系统不会被脚本替换设备树。

## 手动安装HDMI显示文件

如果不用 `install.sh`，把本包的 **`B3Pro` 文件夹和 `u-boot.ext`** 放进当前系统的 `/boot`，先确认 `/boot/u-boot.emmc` 不存在，再以 root 身份执行：

```bash
set -e
test "$(sha256sum /boot/u-boot.ext | cut -d ' ' -f 1)" = 80144d71bb35ce37ae54bb41549d03b0dd1d6bdf6d852766e641477d90e955d8
test ! -e /boot/u-boot.emmc
install -d -m 0755 /usr/local/lib/b3pro
install -m 0644 /boot/u-boot.ext /usr/local/lib/b3pro/u-boot-2026.ext
install -m 0755 /boot/B3Pro/b3pro-display-boot-bridge /usr/local/sbin/b3pro-display-boot-bridge
install -m 0644 /boot/B3Pro/b3pro-display-boot-bridge.service /etc/systemd/system/b3pro-display-boot-bridge.service
systemctl daemon-reload
systemctl enable b3pro-display-boot-bridge.service
```

设备树已在标准目录 `/boot/dtb/amlogic/`。

红外可单独运行 `bash /boot/B3Pro/ir/install-ir.sh`；

蓝牙可运行 `apt-get install -y bluez && systemctl enable --now bluetooth`。

不要把 `u-boot.ext` 永久改名放成 `/boot/u-boot.emmc`。

Wi-Fi SDIO 25MHz / 4位；5GHz 5260MHz，信号约 -50dBm；取得 DHCP 地址，经 wlan0 ping 公网 4/4 成功；重启自动连接。

蓝牙：GPIOX_17 shutdown、GPIOX_19 device-wakeup；PWM_E / GPIOX_16 LPO，30518ns 周期、15259ns 占空时间；BCM4356A2.hcd 从 build 0000 更新到 0266；能扫描、与 Mac 配对，重启后 Paired/Bonded 均为 yes。

红外：NECX 前缀 0x8102；方向、返回、主页、菜单、音量、确定键事件实测；重启后 udev 自动加载成功。

以太网实际通信正常；本次会话未收到 speed=1000 的验证输出，不把千兆吞吐标为实测。
音频、GPU、视频硬解未完成实际使用验证。

本包只放启动文件、设备树、红外键表和必要的安装脚本，没有源码、个人 Wi-Fi 密码或蓝牙配对信息。请保留可启动 U 盘作为恢复介质。原 U-Boot 二进制来自用户提供的 B3 Pro USB 适配包；公开再分发时应确认对应源码及许可材料。

---

设备树基础与引导工作参考 [yefx/build-u-boot-dangbei-b3-pro](https://github.com/yefx/build-u-boot-dangbei-b3-pro)，在本次原厂设备树提取和设备实测基础上修正。内核、DTS 和 U-Boot 等派生组件遵循各自上游许可，不因本包改变；本包不是完整上游源码发布。

包含的 u-boot.ext 为此前本地构建、设备上已用的 U-Boot 2026.01 组件。本包提供其来源说明，但未收齐对应完整构建树、配置及所有第三方材料，**公开分发此二进制前需补齐对应源码与许可材料**；不要把本包理解为已完成开源发布合规审查。

参考：[ophub 文档](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/documents/README.cn.md)、 [yefx](https://github.com/yefx/build-u-boot-dangbei-b3-pro)、 [unifreq U-Boot](https://github.com/unifreq/u-boot)、[Amlogic 原厂蓝牙参考驱动](https://github.com/hardkernel/linux/blob/odroidg12-4.9.y/drivers/amlogic/bluetooth/bt_device.c)。

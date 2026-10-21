# 当贝B3Pro刷armbian教程

### 一定要用质量好点的U盘或者固态硬盘！！！！

适用：4GB 当贝 B3 Pro；实测 ophub Armbian 26.11 / Debian trixie / server / 内核 `6.12.112-ophub`。本包不含系统镜像。请保留一只确认能启动的 U 盘作为恢复介质。

## 1. 制作 U 盘

### 写系统镜像

从 [ophub Armbian Releases](https://github.com/ophub/amlogic-s9xxx-armbian/releases) 下载 **amlogic / s922x / trixie / server** 镜像，我测试的内核 6.12.112-ophub。用 balenaEtcher 或 Rufus 写到 U 盘；会清空 U 盘。

打开本包的 `B3Pro-Armbian-Setup` 文件夹，**全选里面的内容**，粘贴到 U 盘 **BOOT 分区根目录**。不要复制最外层文件夹。文件管理器提示处理已有 `dtb` 文件夹时，选“合并”，不要用本包的小文件夹替换镜像原有的整个 `dtb` 文件夹。

```text
BOOT/
├── aml_autoscript
├── u-boot.ext
├── B3Pro/
│   ├── install.sh                 ← 唯一需要手动运行的脚本
│   ├── boot-usb-first.cmd
│   ├── b3pro-display-boot-bridge  ← 显示服务开机时使用，不用手动运行
│   ├── b3pro-display-boot-bridge.service
│   └── ir/dangbei-b3-pro.toml
├── dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb
├── uEnv.txt                       ← 镜像原有文件，不要覆盖
└── 其他镜像原有文件
```

**修改 uEnv.txt 文件**


只改原有 **`BOOT/uEnv.txt` 的一行**，把 `FDT=` 改成：

```text
FDT=/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb
```

保留原来的 `LINUX`、`INITRD` 和 `APPEND` 中的 `root=`。如果 `APPEND` 没有 `rootwait`，在该行末尾加一个空格和 `rootwait`。不同镜像的根分区参数可能不同，所以本包不提供可直接覆盖的通用 `uEnv.txt`。

## 2. 在盒子的 U 盘系统运行一个命令

用 U 盘启动盒子，在 root 终端或 SSH 执行：

```bash
bash /boot/B3Pro/install.sh
```

脚本先确认当前的 `/` 和 `/boot` **确实都来自同一只 USB 盘**，并核对 `uEnv.txt` 的 `root=`。然后逐项询问：

1. 是否安装无 U 盘启动时的 HDMI 显示修复。
2. 是否安装红外支持。
3. 是否安装蓝牙支持。
4. eMMC 安装成功后，是否设置“可启动 USB 优先、否则进入 eMMC”。
5. 是否现在运行 `armbian-install -m no -a yes` 写入 eMMC。

每项只有输入 `y` 才执行，回车或输入 `n` 都跳过。红外和蓝牙是可选项；安装时按 `Ctrl+C` 可中断当前项，脚本会继续后面的步骤。以后在 eMMC 系统重新运行同一个 `install.sh` 可以补装。**刷写 eMMC 前脚本不会为红外或蓝牙联网安装软件包**，避免网络或软件源问题影响刷机；若 USB 系统缺少 `ir-keytable` 或 `bluez`，请在 eMMC 启动后再运行本脚本补装。

选择写入 eMMC 后，脚本会调用原版 `armbian-install`，设备型号、安装目标和文件系统仍按它的提示选择。实测机选择 **0 / Other Customize**：

| 提示 | 填写 |
| --- | --- |
| SoC Name | `s922x` |
| DTB Name | `meson-g12b-dangbei-b3-pro.dtb` |
| UBOOT_OVERLOAD Name | `u-boot.ext` |
| MAINLINE_UBOOT Name | 留空 |
| BOOTLOADER_IMG Name | 留空 |
| 文件系统 | `1` / ext4 |

**确认安装目标是盒子的 eMMC，再继续。** `armbian-install` 若报错或被中断，脚本会停止，不会修改 eMMC 启动顺序。若安装器返回成功，脚本还会检查 eMMC 的根分区、BOOT 文件和 `root=` 指向；缺少 `rootwait` 时会先备份并补上。若选了 USB 优先，再备份 eMMC 原有 `boot.cmd`、`boot.scr`，生成 USB 优先的新脚本。等 `install.sh` 明确完成后，执行 `poweroff`，拔掉 U 盘，再通电测试。选择显示修复的机器会自动热重启一次后显示登录界面。

## 已装好 eMMC，后来要补装功能

先确认 `/` 和 `/boot` 实际来自 eMMC，不能只看登录画面：

```bash
findmnt -no SOURCE /
findmnt -no SOURCE /boot
```

把本包中的 `B3Pro` 文件夹和 `u-boot.ext` 复制到 **eMMC 的 `/boot`**，然后仍运行同一个命令：

```bash
bash /boot/B3Pro/install.sh
```

脚本识别 eMMC 后，只提供显示、红外、蓝牙、USB 优先等选项，**不会运行 `armbian-install`**。若复制的是 U 盘上的 `/boot`，而当前根系统是 eMMC，脚本会拒绝执行；先把文件放到实际运行系统的 eMMC `/boot`。

## 启动顺序与限制

上游 [USB 引导脚本](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/build-armbian/armbian-files/platform-files/amlogic/bootfs/boot.cmd)会扫描 USB，而安装到 eMMC 的 [boot-emmc.cmd](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/build-armbian/armbian-files/platform-files/amlogic/bootfs/boot-emmc.cmd)只扫描 eMMC。本包的 USB 优先选项已在一台 B3 Pro 上验证：有可启动 USB 时 `/` 与 `/boot` 来自 USB；U 盘没有启动配置或拔掉 U 盘时回退 eMMC。若 U 盘启动文件齐全、但 Linux 根文件系统损坏，引导程序无法预先判断，应拔掉该盘后从 eMMC 启动。

---

### 其他：

Wi-Fi SDIO 25MHz / 4位；5GHz 5260MHz，信号约 -50dBm；取得 DHCP 地址，经 wlan0 ping 公网 4/4 成功；重启自动连接。

蓝牙：GPIOX_17 shutdown、GPIOX_19 device-wakeup；PWM_E / GPIOX_16 LPO，30518ns 周期、15259ns 占空时间；BCM4356A2.hcd 从 build 0000 更新到 0266；能扫描、与 Mac 配对，重启后 Paired/Bonded 均为 yes。

红外：NECX 前缀 0x8102；方向、返回、主页、菜单、音量、确定键事件实测；重启后 udev 自动加载成功。

以太网实际通信正常；本次会话未收到 speed=1000 的验证输出，不把千兆吞吐标为实测。
音频、GPU、视频硬解未完成实际使用验证。

本包只放启动文件、设备树、红外键表和必要的安装脚本，没有源码、个人 Wi-Fi 密码或蓝牙配对信息。请保留可启动 U 盘作为恢复介质。原 U-Boot 二进制来自用户提供的 B3 Pro USB 适配包；公开再分发时应确认对应源码及许可材料。

---

设备树基础与引导工作参考 [yefx/build-u-boot-dangbei-b3-pro](https://github.com/yefx/build-u-boot-dangbei-b3-pro)，在本次原厂设备树提取和设备实测基础上修正。内核、DTS 和 U-Boot 等派生组件遵循各自上游许可，不因本包改变；本包不是完整上游源码发布。

包含的 u-boot.ext 为此前本地构建、设备上已用的 U-Boot 2026.01 组件。本包提供其来源说明，但未收齐对应完整构建树、配置及所有第三方材料，**公开分发此二进制前需补齐对应源码与许可材料**；不要把本包理解为已完成开源发布合规审查。

### 参考：
[ophub 文档](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/documents/README.cn.md)、 [yefx](https://github.com/yefx/build-u-boot-dangbei-b3-pro)、 [unifreq U-Boot](https://github.com/unifreq/u-boot)、[Amlogic 原厂蓝牙参考驱动](https://github.com/hardkernel/linux/blob/odroidg12-4.9.y/drivers/amlogic/bluetooth/bt_device.c)。


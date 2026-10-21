# 当贝B3Pro刷armbian教程

适用：4GB 当贝 B3 Pro；实测 ophub Armbian 26.11 / Debian trixie / server / 内核 `6.12.112-ophub`。本包不含系统镜像。请保留一只确认能启动的 U 盘作为恢复介质。

## 1. 制作 U 盘

写系统镜像

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

只改原有 `BOOT/uEnv.txt` 的 `FDT=` 行：

```text
FDT=/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb
```

保留这只 U 盘镜像原有的 `LINUX`、`INITRD` 和 `APPEND` 中的 `root=`。不要复制旧盘或 eMMC 的 `uEnv.txt`，旧 UUID 可能指向另一块磁盘。若 `APPEND` 没有 `rootwait`，在行末加上 ` rootwait`。电脑上不用运行脚本。

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

本包不含个人 Wi-Fi 密码、网卡地址或蓝牙配对信息。U-Boot 二进制和设备树保持原有字节；公开再分发时应确认 U-Boot 对应源码及许可材料。

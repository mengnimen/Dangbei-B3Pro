#!/usr/bin/env bash
# Run as root inside the B3 Pro Armbian system, before or after armbian-install.
set -euo pipefail
die() { echo "停止：$*" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd -P)
expected=80144d71bb35ce37ae54bb41549d03b0dd1d6bdf6d852766e641477d90e955d8
[[ $EUID -eq 0 ]] || die '请以 root 身份运行。'
[[ $here == /boot/B3Pro ]] || die '请先把本包内容复制到当前系统的 /boot 根目录，再运行 /boot/B3Pro/install.sh。'
[[ $(tr -d '\0' </proc/device-tree/model) == *'Dangbei B3 PRO'* ]] || die '设备型号不是实测的 B3 Pro。'
[[ -f /boot/u-boot.ext ]] || die 'BOOT 根目录缺少 u-boot.ext。'
[[ -f /boot/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb ]] || die 'BOOT/dtb/amlogic 缺少 B3 Pro 设备树。'
[[ -f "$here/b3pro-display-boot-bridge" && -f "$here/b3pro-display-boot-bridge.service" ]] || die '文件夹不完整：缺少显示服务。'
[[ $(sha256sum /boot/u-boot.ext | cut -d ' ' -f 1) == "$expected" ]] || die 'U-Boot 校验失败。'
[[ ! -e /boot/u-boot.emmc ]] || die '/boot/u-boot.emmc 已存在，先查明来源。'
sh -n "$here/b3pro-display-boot-bridge" || die '显示脚本语法错误。'

root_device=$(readlink -f "$(findmnt -n -o SOURCE /)")
boot_device=$(readlink -f "$(findmnt -n -o SOURCE /boot)")
root_parent=$(lsblk -n -o PKNAME "$root_device" | head -n 1)
boot_parent=$(lsblk -n -o PKNAME "$boot_device" | head -n 1)
[[ -n "$root_parent" && "$root_parent" == "$boot_parent" ]] || die '/ 和 /boot 不在同一存储设备。'
if [[ -e "/sys/block/${root_parent}boot0" ]]; then
    mode=emmc
elif [[ $(lsblk -dn -o TRAN "/dev/$root_parent" | tr -d '[:space:]') == usb ]]; then
    mode=usb
    [[ -x /usr/sbin/armbian-install ]] || die '当前 USB 系统没有 armbian-install。'
    [[ $(hexdump -n 15 -x /boot/zImage | awk 'NR==1 {print $7}') == 0108 ]] || die '当前镜像的安装方式未经验证。'
    grep -qx 'FDT=/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb' /boot/uEnv.txt || die '请先将 U 盘 BOOT/uEnv.txt 的 FDT 行改为标准设备树路径。'
else
    die '当前系统既不是已识别的 USB 系统，也不是 eMMC 系统。'
fi

install -d -m 0755 /usr/local/lib/b3pro
install -m 0644 /boot/u-boot.ext /usr/local/lib/b3pro/u-boot-2026.ext
install -m 0755 "$here/b3pro-display-boot-bridge" /usr/local/sbin/b3pro-display-boot-bridge
install -m 0644 "$here/b3pro-display-boot-bridge.service" /etc/systemd/system/b3pro-display-boot-bridge.service
systemctl daemon-reload
systemctl enable b3pro-display-boot-bridge.service
echo '显示服务已启用。'

if bash "$here/ir/install-ir.sh"; then
    echo '红外键表已安装。'
else
    echo '红外键表暂未安装；检查网络后可单独运行 ir/install-ir.sh。' >&2
fi
if command -v bluetoothctl >/dev/null; then
    systemctl enable --now bluetooth.service || echo '蓝牙服务启用失败，请检查系统日志。' >&2
elif apt-get update && apt-get install -y bluez; then
    systemctl enable --now bluetooth.service || echo '蓝牙服务启用失败，请检查系统日志。' >&2
else
    echo 'BlueZ 暂未安装；检查网络后安装 bluez。' >&2
fi
echo 'Wi-Fi 和蓝牙的板级配置在已部署的 DTB 中；无线固件由 Armbian 镜像提供。'
if [[ $mode == usb ]]; then
    echo '接下来运行：armbian-install -m no -a yes，按教程选择 eMMC 安装项。'
else
    echo '当前为 eMMC 系统；无需再次运行 armbian-install。'
fi
echo '完成后运行 poweroff，拔掉 U 盘，再重新通电。首次显示前会自动重启一次。'

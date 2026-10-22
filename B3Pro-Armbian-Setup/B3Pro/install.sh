#!/usr/bin/env bash
# One entry point for USB preparation, eMMC installation, and later additions.
set -euo pipefail

die() { printf '停止：%s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
here=$(cd "$(dirname "$0")" && pwd -P)
expected_uboot=80144d71bb35ce37ae54bb41549d03b0dd1d6bdf6d852766e641477d90e955d8
expected_stock_emmc_script=26743987a269dba16a9cd2e56515acf26daedc39e1675cfd86f9d3f315ae0795

ask_yes() {
    local reply
    trap ':' INT
    if reply=$(trap 'exit 130' INT; printf '%s [y/N] ' "$1" >&2; IFS= read -r answer; printf '%s' "${answer-}"); then
        :
    else
        printf '\n已跳过当前选择。\n'
        reply=n
    fi
    trap - INT
    case "$reply" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

run_optional() {
    local label=$1 status
    shift
    trap 'printf "\n已中断当前可选项，继续下一步。\n"' INT
    if ( trap 'exit 130' INT; "$@" ); then
        say "$label：完成。"
    else
        status=$?
        if [[ $status -eq 2 ]]; then
            say "$label：已延期到 eMMC 系统；以后重新运行 install.sh 补装。"
        else
            say "$label：已跳过或未完成（状态 $status）。以后可重新运行 install.sh。" >&2
        fi
    fi
    trap - INT
}

check_display_payload() {
    [[ -f "$here/b3pro-display-boot-bridge" && -f "$here/b3pro-display-boot-bridge.service" &&
       -f "$here/b3pro-display-warm-reboot.service" && -f "$here/b3pro-display-warm-reboot.timer" &&
       -f "$here/boot-emmc-failsafe.cmd" ]] || return 1
    [[ -f /boot/u-boot.ext ]] || return 1
    [[ $(sha256sum /boot/u-boot.ext | cut -d ' ' -f 1) == "$expected_uboot" ]] || return 1
    sh -n "$here/b3pro-display-boot-bridge" || return 1
    command -v mkimage >/dev/null || return 1
}

install_emmc_failsafe() {
    local boot_dir=$1 source=$here/boot-emmc-failsafe.cmd image size
    [[ -s $boot_dir/emmc_autoscript.cmd && -s $boot_dir/emmc_autoscript ]] || return 1
    size=$(stat -c%s "$source") || return 1
    if cmp -s "$source" "$boot_dir/emmc_autoscript.cmd"; then
        dd if="$boot_dir/emmc_autoscript" bs=1 skip=72 count="$size" status=none | cmp -s - "$source"
        return $?
    fi
    [[ $(sha256sum "$boot_dir/emmc_autoscript.cmd" | cut -d ' ' -f 1) == "$expected_stock_emmc_script" ]] || return 1
    [[ ! -e $boot_dir/emmc_autoscript.cmd.before-b3pro-failsafe &&
       ! -e $boot_dir/emmc_autoscript.before-b3pro-failsafe ]] || return 1
    cp -p "$boot_dir/emmc_autoscript.cmd" "$boot_dir/emmc_autoscript.cmd.before-b3pro-failsafe" || return 1
    cp -p "$boot_dir/emmc_autoscript" "$boot_dir/emmc_autoscript.before-b3pro-failsafe" || return 1
    image=$boot_dir/emmc_autoscript.b3pro-new
    mkimage -C none -A arm -O linux -T script -d "$source" "$image" >/dev/null || return 1
    mkimage -l "$image" >/dev/null || return 1
    dd if="$image" bs=1 skip=72 count="$size" status=none | cmp -s - "$source" || return 1
    cp "$source" "$boot_dir/emmc_autoscript.cmd.b3pro-new" || return 1
    mv "$image" "$boot_dir/emmc_autoscript" || return 1
    mv "$boot_dir/emmc_autoscript.cmd.b3pro-new" "$boot_dir/emmc_autoscript.cmd" || return 1
    sync
}

install_display_to_root() {
    local root_dir=$1
    install -d -m 0755 "$root_dir/usr/local/lib/b3pro" "$root_dir/usr/local/sbin" || return 1
    install -d -m 0755 "$root_dir/etc/systemd/system/multi-user.target.wants" || return 1
    install -m 0644 /boot/u-boot.ext "$root_dir/usr/local/lib/b3pro/u-boot-2026.ext" || return 1
    install -m 0755 "$here/b3pro-display-boot-bridge" "$root_dir/usr/local/sbin/b3pro-display-boot-bridge" || return 1
    install -m 0644 "$here/b3pro-display-boot-bridge.service" "$root_dir/etc/systemd/system/b3pro-display-boot-bridge.service" || return 1
    install -m 0644 "$here/b3pro-display-warm-reboot.service" "$root_dir/etc/systemd/system/b3pro-display-warm-reboot.service" || return 1
    install -m 0644 "$here/b3pro-display-warm-reboot.timer" "$root_dir/etc/systemd/system/b3pro-display-warm-reboot.timer" || return 1
    ln -sfn /etc/systemd/system/b3pro-display-boot-bridge.service \
        "$root_dir/etc/systemd/system/multi-user.target.wants/b3pro-display-boot-bridge.service" || return 1
}

disable_display_in_root() {
    local root_dir=$1
    rm -f "$root_dir/etc/systemd/system/multi-user.target.wants/b3pro-display-boot-bridge.service"
    rm -f "$root_dir/etc/systemd/system/timers.target.wants/b3pro-display-warm-reboot.timer"
}

install_ir() {
    local map=/etc/rc_keymaps/dangbei-b3-pro.toml rule='meson-ir * /etc/rc_keymaps/dangbei-b3-pro.toml'
    local tmp rc found=0
    [[ -f "$here/ir/dangbei-b3-pro.toml" ]] || return 1
    install -d -m 0755 /etc/rc_keymaps || return 1
    if [[ -f $map ]]; then cp -p "$map" "$map.bak-$(date +%Y%m%d-%H%M%S)" || return 1; fi
    install -m 0644 "$here/ir/dangbei-b3-pro.toml" "$map" || return 1
    if ! command -v ir-keytable >/dev/null; then
        if [[ $mode == usb ]]; then
            say '红外键表已放入系统；ir-keytable 留到 eMMC 启动后补装，刷机前不联网。'
            return 2
        fi
        say '正在安装 ir-keytable；按 Ctrl+C 可跳过红外。'
        apt-get update && apt-get install -y ir-keytable || return 1
    fi
    if [[ -f /etc/rc_maps.cfg ]]; then
        cp -p /etc/rc_maps.cfg "/etc/rc_maps.cfg.bak-$(date +%Y%m%d-%H%M%S)" || return 1
        tmp=$(mktemp) || return 1
        printf '%s\n' "$rule" >"$tmp" || return 1
        awk -v rule="$rule" '$0 != rule { print }' /etc/rc_maps.cfg >>"$tmp" || return 1
        cat "$tmp" >/etc/rc_maps.cfg || return 1
        rm -f "$tmp"
        for rc in /sys/class/rc/rc*; do
            [[ -f $rc/uevent ]] || continue
            if grep -q '^DRV_NAME=meson-ir$' "$rc/uevent"; then
                ir-keytable -s "${rc##*/}" -a /etc/rc_maps.cfg || return 1
                found=1
            fi
        done
        [[ $found -eq 1 ]] || say '未发现 meson-ir；键表已保存，下次启动可继续检查。'
    else
        say '系统尚无 rc_maps.cfg；键表已保存。'
    fi
}

install_bluetooth() {
    if ! command -v bluetoothctl >/dev/null; then
        if [[ $mode == usb ]]; then
            say 'USB 系统没有 BlueZ；eMMC 启动后可重跑本脚本补装，刷机前不联网。'
            return 2
        fi
        say '正在安装 bluez；按 Ctrl+C 可跳过蓝牙。'
        apt-get update && apt-get install -y bluez || return 1
    fi
    systemctl enable --now bluetooth.service || return 1
}

apply_usb_first() {
    local boot_dir=$1 source=$here/boot-usb-first.cmd
    [[ -s $source && -s $boot_dir/boot.cmd && -s $boot_dir/boot.scr ]] || return 1
    command -v mkimage >/dev/null || return 1
    if cmp -s "$source" "$boot_dir/boot.cmd"; then
        grep -aq 'B3 Pro: boot USB first' "$boot_dir/boot.scr" || return 1
        say 'USB 优先引导已经安装。'
        return 0
    fi
    grep -Fq 'setenv l_mmc "2 1 0"' "$boot_dir/boot.cmd" || return 1
    [[ ! -e $boot_dir/boot.cmd.before-usb-first && ! -e $boot_dir/boot.scr.before-usb-first ]] || return 1
    cp "$boot_dir/boot.cmd" "$boot_dir/boot.cmd.before-usb-first" || return 1
    cp "$boot_dir/boot.scr" "$boot_dir/boot.scr.before-usb-first" || return 1
    cp "$source" "$boot_dir/boot.cmd.usb-first-new" || return 1
    mkimage -C none -A arm -T script -d "$boot_dir/boot.cmd.usb-first-new" "$boot_dir/boot.scr.usb-first-new" >/dev/null || return 1
    mkimage -l "$boot_dir/boot.scr.usb-first-new" >/dev/null || return 1
    mv "$boot_dir/boot.cmd.usb-first-new" "$boot_dir/boot.cmd" || return 1
    mv "$boot_dir/boot.scr.usb-first-new" "$boot_dir/boot.scr" || return 1
    sync
    say '已设置 USB 优先、eMMC 回退，并备份原引导脚本。'
}

emmc_disk() {
    local entry
    for entry in /sys/block/mmcblk*; do
        [[ -e ${entry}boot0 ]] || continue
        printf '%s\n' "${entry##*/}"
        return 0
    done
    return 1
}

preflight_install() {
    local emmc=$1 source_used target_size
    source_used=$(df -B1 --output=used / | tail -n 1 | tr -d '[:space:]') || die '无法读取 USB 根分区的已用空间。'
    target_size=$(blockdev --getsize64 "/dev/$emmc") || die '无法读取 eMMC 容量。'
    [[ $source_used =~ ^[0-9]+$ && $target_size =~ ^[0-9]+$ ]] || die '磁盘容量检测结果无效。'
    (( source_used + 3 * 1024 * 1024 * 1024 < target_size )) ||
        die 'USB 根分区已用空间接近或超过 eMMC 可用容量；保留当前 USB，不要刷写。'
    say '正在只读检查 USB 系统的 /usr 文件；这一步可能需要几分钟。'
    if ! (cd / && tar -cf /dev/null usr); then
        die 'USB 系统的 /usr 读取失败。不要格式化 eMMC；先检查 USB 盘、接口和供电。'
    fi
    source_usr_files=$(find /usr -type f | wc -l | tr -d '[:space:]') || die '无法统计 USB 系统的 /usr 文件。'
    [[ $source_usr_files =~ ^[0-9]+$ && $source_usr_files -gt 0 ]] || die 'USB 系统的 /usr 文件数量异常。'
    say 'USB 来源盘的容量与 /usr 读取检查通过。'
}

verify_emmc_root() (
    local device=$1 target target_usr_files
    target=$(mktemp -d /tmp/b3pro-emmc-root.XXXXXX) || return 1
    trap 'if mountpoint -q "$target"; then umount "$target" || true; fi; rmdir "$target" 2>/dev/null || true' EXIT
    mount -t ext4 -o ro,noload "$device" "$target" || return 1
    [[ -x $target/usr/bin/bash && -x $target/usr/bin/tar && -x $target/usr/bin/ls ]] || return 1
    [[ -s $target/etc/os-release ]] || return 1
    target_usr_files=$(find "$target/usr" -type f | wc -l | tr -d '[:space:]') || return 1
    [[ $target_usr_files =~ ^[0-9]+$ ]] || return 1
    (( target_usr_files >= source_usr_files * 99 / 100 )) || return 1
)

check_usb_root() {
    local uenv_root configured_root
    [[ -x /usr/sbin/armbian-install ]] || die '当前 USB 系统没有 armbian-install。'
    [[ $(hexdump -n 15 -x /boot/zImage | awk 'NR==1 {print $7}') == 0108 ]] || die '当前镜像的安装方式未经验证。'
    grep -qx 'FDT=/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb' /boot/uEnv.txt || die '请先修正 USB BOOT/uEnv.txt 的 FDT 行。'
    uenv_root=$(awk '/^APPEND=/{for (i=1;i<=NF;i++) {value=$i; sub(/^APPEND=/,"",value); if (value~/^root=/) {sub(/^root=/,"",value); print value; exit}}}' /boot/uEnv.txt)
    [[ -n $uenv_root ]] || die 'USB BOOT/uEnv.txt 缺少 root= 参数。'
    if [[ $uenv_root == /dev/* ]]; then
        configured_root=$(readlink -f "$uenv_root")
    else
        configured_root=$(findfs "$uenv_root" 2>/dev/null) || die "找不到 root=$uenv_root 的分区。"
        configured_root=$(readlink -f "$configured_root")
    fi
    [[ $configured_root == "$root_device" ]] || die "USB BOOT 的 root=$uenv_root 与当前 USB 根分区 $root_device 不一致。"
}

[[ $EUID -eq 0 ]] || die '请以 root 身份运行。'
[[ $here == /boot/B3Pro ]] || die '请把本包内容放入当前系统的 /boot 根目录。'
[[ $(tr -d '\0' </proc/device-tree/model) == *'Dangbei B3 PRO'* ]] || die '设备型号不是实测的 B3 Pro。'
[[ -f /boot/dtb/amlogic/meson-g12b-dangbei-b3-pro.dtb ]] || die 'BOOT 中缺少 B3 Pro 设备树。'
[[ -f /boot/u-boot.ext ]] || die 'BOOT 根目录缺少 u-boot.ext。'
[[ $(sha256sum /boot/u-boot.ext | cut -d ' ' -f 1) == "$expected_uboot" ]] || die 'U-Boot 校验失败。'
root_device=$(readlink -f "$(findmnt -n -o SOURCE /)")
boot_device=$(readlink -f "$(findmnt -n -o SOURCE /boot)")
root_parent=$(lsblk -n -o PKNAME "$root_device" | head -n 1)
boot_parent=$(lsblk -n -o PKNAME "$boot_device" | head -n 1)
[[ -n $root_parent && $root_parent == "$boot_parent" ]] || die '/ 和 /boot 不在同一存储设备。'

if [[ -e /sys/block/${root_parent}boot0 ]]; then
    mode=emmc
    [[ $# -eq 0 || ( $# -eq 1 && $1 == --existing-emmc ) ]] || die '不支持的参数。'
else
    [[ $(lsblk -dn -o TRAN "/dev/$root_parent" | tr -d '[:space:]') == usb ]] || die '当前既不是已识别的 USB 系统，也不是 eMMC 系统。'
    mode=usb
    [[ $# -eq 0 ]] || die '在 USB 系统运行时不需要参数。'
    check_usb_root
fi

say "当前运行：$mode 系统；根分区 $root_device；BOOT 分区 $boot_device。"
say '红外、蓝牙是可选项：输入 n 或直接回车可跳过；安装时按 Ctrl+C 可中断当前项，以后再运行本脚本补装。'

display_requested=no
if ask_yes '安装无 U 盘时的 HDMI 显示修复吗？'; then
    check_display_payload || die '显示修复文件、U-Boot 校验或 mkimage 检查失败。'
    display_requested=yes
    if [[ $mode == emmc ]]; then
        install_emmc_failsafe /boot || die 'eMMC 引导保护安装失败；请先检查备份。'
        install_display_to_root / || die '显示服务安装失败；请先检查。'
        systemctl daemon-reload
        say '显示修复与单次引导保护：已安装。'
    else
        say '显示修复文件检查通过；写入 eMMC 并核验成功后才会安装到 eMMC。'
    fi
fi
if ask_yes '安装红外支持吗？'; then run_optional '红外' install_ir; fi
if ask_yes '安装蓝牙支持吗？'; then run_optional '蓝牙' install_bluetooth; fi
say 'Wi-Fi 的板级配置已包含在设备树中，固件由 Armbian 镜像提供。'

if [[ $mode == emmc ]]; then
    if ask_yes '设置可启动 USB 优先、无系统 USB 回退 eMMC 吗？'; then
        apply_usb_first /boot || die 'USB 优先设置失败；原引导文件备份仍保留，请检查。'
    fi
    say '当前是 eMMC 系统，不会运行 armbian-install。以后可重跑本脚本补装可选项。'
    exit 0
fi

usb_first=no
if ask_yes '安装 eMMC 后启用 USB 优先启动吗？'; then
    command -v mkimage >/dev/null || die '缺少 mkimage（u-boot-tools），无法生成 USB 优先引导脚本。'
    [[ -s $here/boot-usb-first.cmd ]] || die '缺少 USB 优先引导源文件。'
    usb_first=yes
fi

say '安装器会复制当前 USB 系统到 eMMC，包括账号、密码、网络配置和首次登录状态；eMMC 不会重新出现全新系统的初始化提示。'
say '只有确认当前根系统来自 USB 且安装目标是盒子的 eMMC，才继续。安装器将继续让你选择设备型号和文件系统。'
if ! ask_yes '现在运行 armbian-install 写入 eMMC 吗？'; then
    say '已跳过 eMMC 安装；USB 系统中的可选配置已保留。以后可重跑 install.sh。'
    exit 0
fi

emmc=$(emmc_disk) || die '找不到 eMMC 设备。'
preflight_install "$emmc"
say "将运行 armbian-install；请确认安装目标是 /dev/$emmc。"
before_dmesg_lines=$(dmesg | wc -l | tr -d '[:space:]')
if ! armbian-install -m no -a yes; then
    die 'armbian-install 未成功完成。不要从 eMMC 启动；保留完整报错，先检查安装结果。'
fi

emmc_boot=/dev/${emmc}p1
emmc_root=/dev/${emmc}p2
[[ $(blkid -s TYPE -o value "$emmc_boot") == vfat ]] || die 'eMMC BOOT 文件系统不是预期的 vfat，无法确认安装成功。'
[[ $(blkid -s TYPE -o value "$emmc_root") == ext4 ]] || die 'eMMC 根分区不是预期的 ext4，无法确认安装成功。'
verify_emmc_root "$emmc_root" || die 'eMMC 根分区的关键文件或 /usr 文件数量不完整。安装失败，不要拔掉 USB 后启动。'
target=$(mktemp -d /tmp/b3pro-emmc-boot.XXXXXX)
mount "$emmc_boot" "$target" || die '无法挂载 eMMC BOOT，无法确认安装成功。'
cleanup_target() {
    if mountpoint -q "$target"; then umount "$target" || true; fi
    rmdir "$target" 2>/dev/null || true
}
trap cleanup_target EXIT
if [[ ! -s $target/uEnv.txt || ! -s $target/zImage || ! -s $target/uInitrd || ! -s $target/boot.scr ]]; then
    die 'eMMC BOOT 文件不完整；没有更改启动顺序，请检查安装结果。'
fi
[[ ! -e $target/u-boot.emmc ]] || die 'eMMC BOOT 上存在未清理的临时 u-boot.emmc；请保留 USB 救援盘，先检查来源。'
uenv_root=$(awk '/^APPEND=/{for (i=1;i<=NF;i++) {value=$i; sub(/^APPEND=/,"",value); if (value~/^root=/) {sub(/^root=/,"",value); print value; exit}}}' "$target/uEnv.txt")
[[ -n $uenv_root ]] || die 'eMMC BOOT 的 uEnv.txt 缺少 root=，请检查安装结果。'
if [[ $uenv_root == /dev/* ]]; then
    configured_root=$(readlink -f "$uenv_root")
else
    configured_root=$(findfs "$uenv_root" 2>/dev/null) || die 'eMMC BOOT 的 root= 找不到对应分区。'
    configured_root=$(readlink -f "$configured_root")
fi
[[ $configured_root == "$(readlink -f "$emmc_root")" ]] || die "eMMC BOOT 的 root=$uenv_root 未指向 $emmc_root；停止后续修改。"
fdt=$(sed -n 's/^FDT=//p' "$target/uEnv.txt" | head -n 1)
[[ -n $fdt && -s $target/$fdt ]] || die 'eMMC BOOT 中找不到设备树文件，请检查安装结果。'
if ! grep '^APPEND=' "$target/uEnv.txt" | grep -Eq '(^|[[:space:]])rootwait([[:space:]]|$)'; then
    cp "$target/uEnv.txt" "$target/uEnv.txt.before-rootwait" || die '无法备份 eMMC uEnv.txt。'
    awk '/^APPEND=/ {$0=$0 " rootwait"} {print}' "$target/uEnv.txt" >"$target/uEnv.txt.with-rootwait" || die '无法写入 rootwait。'
    mv "$target/uEnv.txt.with-rootwait" "$target/uEnv.txt" || die '无法更新 eMMC uEnv.txt。'
    say '已为 eMMC 启动参数添加 rootwait，并备份原 uEnv.txt。'
fi
if [[ $usb_first == yes ]]; then
    if ! apply_usb_first "$target"; then
        die 'eMMC 引导脚本更新失败；请检查备份和安装结果。'
    fi
fi
if [[ $display_requested == yes ]]; then
    install_emmc_failsafe "$target" || die 'eMMC 的单次引导保护安装失败；请保留 USB 救援盘。'
fi

target_root=$(mktemp -d /tmp/b3pro-emmc-postinstall.XXXXXX)
mount "$emmc_root" "$target_root" || die '无法挂载 eMMC 根分区；请保留 USB 救援盘。'
cleanup_root() {
    if mountpoint -q "$target_root"; then umount "$target_root" || true; fi
    rmdir "$target_root" 2>/dev/null || true
}
trap 'cleanup_root; cleanup_target' EXIT
if [[ $display_requested == yes ]]; then
    install_display_to_root "$target_root" || die '无法向 eMMC 根分区安装显示服务；请保留 USB 救援盘。'
    say '显示服务已安装到 eMMC。'
else
    disable_display_in_root "$target_root" || die '无法关闭 eMMC 上克隆来的旧显示服务。'
    say '已确保 eMMC 不会启动克隆来的显示服务。'
fi
umount "$target_root" || die '无法卸载 eMMC 根分区；请先检查，暂时不要断电。'
rmdir "$target_root"
trap cleanup_target EXIT
umount "$target" || die '无法卸载 eMMC BOOT，请先检查，暂时不要断电。'
rmdir "$target"
trap - EXIT

new_storage_errors=$(dmesg | tail -n "+$((before_dmesg_lines + 1))" | grep -Ei 'I/O error|Buffer I/O|EXT4-fs error|uas_eh_|reset SuperSpeed USB device|mmc_erase: erase error|cache flush error' || true)
if [[ -n $new_storage_errors ]]; then
    printf '%s\n' "$new_storage_errors" >&2
    die '安装期间出现存储错误。即使安装器报告成功，也请保留救援 U 盘并先核验 eMMC。'
fi
say 'eMMC 安装已结束。请先检查安装器没有报错，再运行 poweroff，拔掉 USB 后通电测试。'
say '如果选择了显示修复，冷启动后请等待约三分钟，系统会自动热重启一次。'
say '若三分钟后仍黑屏，请断电再开一次以触发原引导回退；不要反复重跑安装器。'
say '以后可在 eMMC 系统重跑本脚本补装红外或蓝牙。'

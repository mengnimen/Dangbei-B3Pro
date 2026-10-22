echo "B3 Pro: boot USB first, then eMMC"
if printenv bootfromsd; then exit; fi;
setenv loadaddr 0x44000000
setenv kernel_addr_r 0x11000000
setenv ramdisk_addr_r 0x15000000
setenv fdt_addr_r 0x1000000
usb start
for devtype in usb mmc; do
    if test "${devtype}" = usb; then
        setenv devices "0 1 2 3"
    else
        setenv devices "2 1 0"
    fi
    for devnum in ${devices}; do
        if test -e ${devtype} ${devnum} uEnv.txt; then
            if load ${devtype} ${devnum} ${loadaddr} uEnv.txt; then
                env import -t ${loadaddr} ${filesize}
                setenv bootargs ${APPEND}
                if printenv mac; then
                    setenv bootargs ${bootargs} mac=${mac}
                elif printenv eth_mac; then
                    setenv bootargs ${bootargs} mac=${eth_mac}
                elif printenv ethaddr; then
                    setenv bootargs ${bootargs} mac=${ethaddr}
                fi
                if load ${devtype} ${devnum} ${kernel_addr_r} ${LINUX}; then
                    if load ${devtype} ${devnum} ${ramdisk_addr_r} ${INITRD}; then
                        if load ${devtype} ${devnum} ${fdt_addr_r} ${FDT}; then
                            fdt addr ${fdt_addr_r}
                            booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
                        fi
                    fi
                fi
            fi
        fi
    done
done

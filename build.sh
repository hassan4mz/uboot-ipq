#!/bin/bash

set -e
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

show_help() {
    echo -e "${CYAN}用法:${RESET} $0 <board-name1> [board-name2 ...]"
    echo ""
    echo "命令列表:"
    echo -e "  ${YELLOW}all${RESET}           编译 include/configs/ 下所有板子"
    echo -e "  ${YELLOW}clean${RESET}         清理构建输出"
    echo -e "  ${YELLOW}distclean${RESET}     更彻底地清理构建输出"
    echo -e "  ${YELLOW}help${RESET}          显示此帮助信息"
    echo ""
    echo "支持的 board 名称:"
    if [ -d include/configs ]; then
        find include/configs -maxdepth 1 -type f -name "ipq40xx_*.h" \
            | sed 's|.*/ipq40xx_||; s|\.h$||' | sort | sed 's/^/  - /'
    else
        echo "  (未找到 include/configs 目录)"
    fi
}

build_board() {
    local board=$1
    local config_file="include/configs/ipq40xx_${board}.h"

    export BUILD_TOPDIR=$(pwd)
    local LOGFILE="${BUILD_TOPDIR}/build.log"
    echo -e "\n==== 构建 $board ====\n" >> "$LOGFILE"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}❌ 错误: 未找到配置文件: ${config_file}${RESET}" | tee -a "$LOGFILE"
        return 1
    fi

    echo -e "${CYAN}===> 编译板子: ${board}${RESET}" | tee -a "$LOGFILE"

    export STAGING_DIR=/home/a/uboot-ipq40xx1/openwrt-sdk-ipq806x-qsdk53/staging_dir
    export TOOLPATH=${STAGING_DIR}/toolchain-arm_cortex-a7_gcc-4.8-linaro_uClibc-1.0.14_eabi/
    export PATH=${TOOLPATH}/bin:${PATH}
    export MAKECMD="make --silent ARCH=arm CROSS_COMPILE=arm-openwrt-linux-"
    export CONFIG_BOOTDELAY=1
    export MAX_UBOOT_SIZE=524288

    mkdir -p "${BUILD_TOPDIR}/bin"

    echo "===> 配置: ipq40xx_${board}_config" | tee -a "$LOGFILE"
    ${MAKECMD} ipq40xx_${board}_config 2>&1 | tee -a "$LOGFILE"

    echo "===> 编译中..." | tee -a "$LOGFILE"
    ${MAKECMD} ENDIANNESS=-EB V=1 all 2>&1 | tee -a "$LOGFILE"

    if [[ ! -f "u-boot" ]]; then
        echo -e "${RED}❌ 错误: 未生成 u-boot 文件${RESET}" | tee -a "$LOGFILE"
        return 1
    fi

    local out_elf="${BUILD_TOPDIR}/bin/openwrt-${board}-u-boot-stripped.elf"
    cp u-boot "$out_elf"
    arm-openwrt-linux-objcopy --strip-all "$out_elf"

    local size
    size=$(stat -c%s "$out_elf")
    if [[ $size -gt $MAX_UBOOT_SIZE ]]; then
        echo -e "${RED}⚠️ 警告: u-boot 文件大小超出限制 (${size} bytes)${RESET}" | tee -a "$LOGFILE"
    fi

    (
        cd "$(dirname "$out_elf")"
        md5sum "$(basename "$out_elf")" > "$(basename "$out_elf").md5"
    )

    echo -e "${GREEN}✅ 编译完成: $(basename "$out_elf")${RESET}" | tee -a "$LOGFILE"
    echo -e "${GREEN}✅ 生成校验: $(basename "$out_elf").md5${RESET}" | tee -a "$LOGFILE"

    # 打包成 zip，输出在 bin/
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local zipfile="${BUILD_TOPDIR}/bin/output-${board}-${timestamp}.zip"
    (
        cd "${BUILD_TOPDIR}/bin"
        zip -9qr "$zipfile" . > /dev/null
    )
    echo -e "${GREEN}📦 打包成功: $(basename "$zipfile")${RESET}" | tee -a "$LOGFILE"
}

clean_build() {
    echo -e "${YELLOW}===> 清理构建文件...${RESET}"
    rm -rf ./bin build.log
    rm -f .depend
    find . -type f \( \
        -name "*.o" -or -name "*.su" -or -name "*.a" -or \
        -name "*.map" -or -name "*.bin" -or -name "*.s" -or \
        -name "*.srec" -or -name "*.depend*" -or \
        -name "u-boot" -or -name "envcrc" \
    \) -exec rm -f {} \;

    # 删除指定路径和文件
    rm -rf \
        arch/arm/include/asm/arch \
        arch/arm/include/asm/proc \
        examples/standalone/hello_world \
        include/asm \
        include/autoconf.mk \
        include/autoconf.mk.dep \
        include/config.h \
        include/config.mk \
        include/generated \
        tools/dumpimage \
        tools/gen_eth_addr \
        tools/mkenvimage \
        tools/mkimage \
        u-boot.lds

    if [[ -d ./uboot ]]; then
        cd ./uboot
        make --silent clean || echo "提示: uboot 目录下无 clean 目标"
        cd ..
    fi
    echo -e "${GREEN}===> 清理完成${RESET}"
}


# 主入口
case "$1" in
    clean)
        clean_build
        ;;
    distclean)
        distclean_build
        ;;
    help|-h|--help)
        show_help
        ;;
    all)
        echo -e "${CYAN}===> 编译 include/configs 中所有 board...${RESET}"
        boards=$(find include/configs -maxdepth 1 -name 'ipq40xx_*.h' | sed 's|.*/ipq40xx_||; s|\.h$||' | sort)
        for board in $boards; do
            build_board "$board"
        done
        ;;
    "")
        echo -e "${RED}❌ 错误: 未指定命令或板子名称${RESET}"
        show_help
        exit 1
        ;;
    *)
        shift 0
        for board in "$@"; do
            build_board "$board"
        done
        ;;
esac


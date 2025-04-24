#!/bin/bash

set -e
set -o pipefail

show_help() {
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令列表:"
    echo "  board <name>          编译指定的 U-Boot 板级配置（如 ipq40xx）"
    echo "  clean                 清理构建输出"
    echo "  distclean             清理构建输出并执行更彻底的清理"
    echo "  help                  显示此帮助信息"
}

build_board() {
    local board=$1

    if [[ -z "$board" ]]; then
        echo "错误: 请提供 board 名称，例如: $0 board ipq40xx"
        exit 1
    fi

    echo "===> 开始为板子 '$board' 编译 u-boot..."

    export BUILD_TOPDIR=$(pwd)
    export STAGING_DIR=/home/a/uboot-ipq40xx1/openwrt-sdk-ipq806x-qsdk53/staging_dir
    export TOOLPATH=${STAGING_DIR}/toolchain-arm_cortex-a7_gcc-4.8-linaro_uClibc-1.0.14_eabi/
    export PATH=${TOOLPATH}/bin:${PATH}
    export MAKECMD="make --silent ARCH=arm CROSS_COMPILE=arm-openwrt-linux-"
    export CONFIG_BOOTDELAY=1
    export MAX_UBOOT_SIZE=524288  # 512KB

    mkdir -p ${BUILD_TOPDIR}/bin

    echo "===> 配置 uboot for $board"
    cd ${BUILD_TOPDIR}
    eval ${MAKECMD} ipq40xx_${board}_config

    echo "===> 编译 uboot for $board"
    eval ${MAKECMD} ENDIANNESS=-EB V=1 all

    echo "===> 拷贝并 strip ELF 文件"

    if [ -f "u-boot" ]; then
        local out_elf=${BUILD_TOPDIR}/bin/openwrt-${board}-u-boot-stripped.elf
        cp u-boot "$out_elf"
        echo "===> 使用 objcopy 执行 strip 操作"
        arm-openwrt-linux-objcopy --strip-all "$out_elf"

        size=$(stat -c%s "$out_elf")
        if [ $size -gt $MAX_UBOOT_SIZE ]; then
            echo "WARNING: image size too big ($size bytes), do not flash it!"
        fi

        cp "$out_elf" ${BUILD_TOPDIR}/bin/u-boot.bin
    else
        echo "❌ 错误: 未找到 u-boot 文件，可能编译失败"
        exit 1
    fi

    echo "✅ 板子 '$board' 的编译完成"
}

clean_build() {
    echo "===> 清理构建目录..."
    rm -rf ./bin
    rm -f .depend  # 删除 .depend
    find . -type f \( \
        -name "*.o" -or \
        -name "*.su" -or \
        -name "*.a" -or \
        -name "*.map" -or \
        -name "*.bin" -or \
        -name "*.s" -or \
        -name "*.srec" -or \
        -name "*.depend*" -or \
        -name "envcrc" -or \
        -name "u-boot" \
    \) -exec rm -f {} \;

    if [ -d "./uboot" ]; then
        cd ./uboot
        make --silent clean || echo "uboot 目录下没有 clean 目标，已跳过"
        cd ..
    fi
    echo "===> 清理完成"
}

distclean_build() {
    clean_build
    echo "===> 执行 distclean，彻底清理构建文件..."
    if [ -d "./uboot" ]; then
        cd ./uboot
        make --silent distclean || echo "uboot 目录下没有 distclean 目标，已跳过"
        cd ..
    fi
    echo "===> 完成 distclean"
}

# 命令解析
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
    *)
        build_board "$1"
        ;;
esac


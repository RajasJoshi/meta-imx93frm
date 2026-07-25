FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
DEPENDS += "u-boot-tools-native"

SRC_URI += " file://0001-imx93-enable-env_redunand-bootcount-limit-lf-6.18.2-1.0.0.patch \
    file://0002-imx93-default-env-lf-6.18.2-1.0.0.patch \
    file://uboot-default-env.txt \
    "

do_install:append() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${DEPLOY_DIR_IMAGE}/u-boot-imx-initial-env-${MACHINE}-sd  ${D}${sysconfdir}/u-boot-imx-initial-env
}

do_image_wic:append() {
    W="${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.wic"

    # -r because your U-Boot has CONFIG_ENV_OFFSET_REDUND (two-line fw_env.config)
    mkenvimage -s 0x4000 -r -o ${WORKDIR}/env.bin ${UNPACKDIR}/uboot-default-env.txt

    # primary at 0x700000, redundant at 0x704000
    dd if=${WORKDIR}/env.bin of=$W bs=4k seek=$((0x700000/4096)) conv=notrunc
    dd if=${WORKDIR}/env.bin of=$W bs=4k seek=$((0x704000/4096)) conv=notrunc
}
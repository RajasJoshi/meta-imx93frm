# meta-imx93frm/recipes-bsp/u-boot-env-blob/u-boot-env-blob.bb
DESCRIPTION = "Binary U-Boot env blobs (CRC'd) for flashing"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "u-boot-tools-native u-boot-imx"
inherit deploy

ENV_SIZE ?= "0x20000"
INITIAL_ENV ?= "u-boot-imx-initial-env-${MACHINE}-sd"

do_compile[depends] += "u-boot-imx:do_deploy"

do_compile() {
    if [ ! -f "${DEPLOY_DIR_IMAGE}/${INITIAL_ENV}" ]; then
        bbfatal "initial env not found: ${DEPLOY_DIR_IMAGE}/${INITIAL_ENV}"
    fi

    mkenvimage -s ${ENV_SIZE} -o ${B}/uboot-env.bin \
        ${DEPLOY_DIR_IMAGE}/${INITIAL_ENV}

    actual=$(stat -c %s ${B}/uboot-env.bin)
    expected=$(printf "%d" ${ENV_SIZE})
    if [ "$actual" != "$expected" ]; then
        bbfatal "uboot-env.bin is $actual bytes, expected $expected"
    fi
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/uboot-env.bin        ${DEPLOYDIR}/uboot-env.bin
}
addtask deploy after do_compile before do_build
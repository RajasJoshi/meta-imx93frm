SUMMARY = "FRDM-IMX93 A/B OTA update artifact"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit swupdate

FILESEXTRAPATHS:prepend := "${DEPLOY_DIR_IMAGE}:"

SRC_URI = "file://sw-description \
           file://Image \
           file://tee.bin \
           file://imx93-11x11-frdm.dtb"

IMAGE_DEPENDS = "swupdate-image"

SWUPDATE_IMAGES = "swupdate-image"
SWUPDATE_IMAGES_FSTYPES[swupdate-image] = ".rootfs.ext4.gz"

BOOT_FILES ?= "Image tee.bin imx93-11x11-frdm.dtb"

do_stage_swu_artifacts() {
    for f in ${BOOT_FILES}; do
        cp ${DEPLOY_DIR_IMAGE}/$f ${WORKDIR}/$f
    done
}
addtask stage_swu_artifacts before do_swuimage after do_unpack
do_stage_swu_artifacts[depends] += "swupdate-image:do_image_complete"
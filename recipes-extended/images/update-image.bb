# meta-imx93frdm/recipes-core/images/update-image.bb
DESCRIPTION = "FRDM-IMX93 SWUpdate OTA package (A/B, no rescue)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit swupdate

SRC_URI = "file://sw-description \
    file://preinst.sh \
    file://postinst.sh \
"

IMAGE_DEPENDS = "swupdate-image"

SWUPDATE_IMAGES = "fitImage swupdate-image"
SWUPDATE_IMAGES_FSTYPES[fitImage] = ""
SWUPDATE_IMAGES_FSTYPES[swupdate-image] = ".rootfs.ext4.gz"

SWUPDATE_IMAGES_ENCRYPTED[fitImage] = "1"
SWUPDATE_IMAGES_ENCRYPTED[swupdate-image] = "1"

BOOT_FILES ?= "fitImage"

do_stage_swu_artifacts() {
    for f in ${BOOT_FILES}; do
        cp ${DEPLOY_DIR_IMAGE}/$f ${WORKDIR}/$f
    done
}
addtask stage_swu_artifacts before do_swuimage after do_unpack

do_stage_swu_artifacts[depends] += "linux-imx-fitimage:do_deploy"

do_swuimage[depends] += " \
    swupdate-image:do_image_complete \
    linux-imx-fitimage:do_deploy \
"
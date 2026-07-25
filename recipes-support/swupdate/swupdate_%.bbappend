FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FILES:${PN} += "/www/*"

SRC_URI += " \
    file://swupdate-sysrestart.service \
    file://swupdate.cfg \
    file://swu_public.pem \
    file://0001-mongoose-enable-cgi.patch \
    file://sysinfo.cgi \
"

FILES:${PN} += " \
    ${systemd_system_unitdir}/swupdate-sysrestart.service \
"

RDEPENDS:${PN}-www += "bash"

SYSTEMD_SERVICE:${PN} += "swupdate-sysrestart.service"

do_install:append() {
    install -m 644 ${UNPACKDIR}/swupdate.cfg ${D}${sysconfdir}/swupdate.cfg
    install -m 644 ${UNPACKDIR}/swu_public.pem ${D}${sysconfdir}/swu_public.pem
    install -m 644 ${UNPACKDIR}/swupdate-sysrestart.service ${D}${systemd_system_unitdir}/swupdate-sysrestart.service
    install -m 0755 ${UNPACKDIR}/sysinfo.cgi ${D}/www/sysinfo.cgi
}

do_image_wic:append() {
    W="${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.wic"
    D="${DEPLOY_DIR_IMAGE}"

    # rescue kernel, dtb, ramdisk into the reserved 8M-120M raw region
    dd if=${D}/Image                              of=$W bs=512 seek=$((0x4000))  conv=notrunc
    dd if=${D}/imx93-11x11-frdm.dtb               of=$W bs=512 seek=$((0x19000)) conv=notrunc
    dd if=${D}/${IMAGE_LINK_NAME}.cpio.gz.u-boot  of=$W bs=512 seek=$((0x1B000)) conv=notrunc
}
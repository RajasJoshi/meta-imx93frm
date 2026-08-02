# recipes-core/usb-automount/usb-automount.bb
DESCRIPTION = "udev-triggered automount for USB mass-storage via systemd-mount"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = "file://99-usb-automount.rules \
    file://data.mount \
    "

RDEPENDS:${PN} += "systemd udev"
SYSTEMD_SERVICE:${PN} += "data.mount"

do_install() {
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${UNPACKDIR}/99-usb-automount.rules ${D}${sysconfdir}/udev/rules.d/99-usb-automount.rules

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/data.mount ${D}${systemd_system_unitdir}/data.mount
    install -d ${D}/data
}

FILES:${PN} = "${sysconfdir}/udev/rules.d/99-usb-automount.rules \
    ${systemd_system_unitdir}/data.mount \
    /data \
    "
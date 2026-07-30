FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FILES:${PN} += "/www/*"

SRC_URI += " \
    file://swupdate-sysrestart.service \
    file://swupdate.cfg \
    file://${SWUPDATE_PUBLIC_KEY} \
    file://swu_aes.key \
    file://0001-mongoose-enable-cgi.patch \
    file://sysinfo.cgi \
"

FILES:${PN} += " \
    ${systemd_system_unitdir}/swupdate-sysrestart.service \
    ${sysconfdir}/swupdate.cfg \
    ${sysconfdir}/swu_public.pem \
    ${sysconfdir}/swu_aes.key \
"

RDEPENDS:${PN}-www += "bash"

SYSTEMD_SERVICE:${PN} += "swupdate-sysrestart.service"

do_install:append() {
    install -m 0644 ${UNPACKDIR}/swupdate.cfg   ${D}${sysconfdir}/swupdate.cfg
    install -m 0644 ${SWUPDATE_PUBLIC_KEY}  ${D}${sysconfdir}/swu_public.pem
    install -m 0600 ${UNPACKDIR}/swu_aes.key    ${D}${sysconfdir}/swu_aes.key
    install -m 0644 ${UNPACKDIR}/swupdate-sysrestart.service ${D}${systemd_system_unitdir}/swupdate-sysrestart.service
    install -m 0755 ${UNPACKDIR}/sysinfo.cgi ${D}/www/sysinfo.cgi
}

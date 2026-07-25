FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://fw_env.config file://hwrevision"
do_install:append() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${UNPACKDIR}/fw_env.config ${D}${sysconfdir}/fw_env.config
    install -m 0644 ${UNPACKDIR}/hwrevision    ${D}${sysconfdir}/hwrevision
}
FILES:${PN} += "${sysconfdir}/fw_env.config ${sysconfdir}/hwrevision"
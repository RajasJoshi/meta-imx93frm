IMAGE_INSTALL = "base-files \
		base-passwd \
		busybox \
		libconfig \
		swupdate \
		swupdate-www \
        ${@bb.utils.contains('SWUPDATE_INIT', 'tiny', 'virtual/initscripts-swupdate', 'initscripts systemd', d)} \
		util-linux-sfdisk \
		mmc-utils \
		e2fsprogs-resize2fs \
		lua \
		libubootenv-bin \
		wireless-regdb \
		automount \
		 "

IMAGE_FSTYPES = "ext4.gz.u-boot ext4.gz cpio.gz.u-boot wic.zst"

PACKAGE_EXCLUDE += " jailhouse kernel-module-jailhouse libncursesw5 libpanelw5 libpython3 python3*  perl* apt dpkg "

# main FIT lands in the boot slots via bootimg-partition
IMAGE_BOOT_FILES = "fitImage"

# wic needs the main FIT deployed before it assembles the card
do_image_wic[depends] += " linux-imx-fitimage:do_deploy "

do_image_wic[depends] += " u-boot-env-blob:do_deploy "

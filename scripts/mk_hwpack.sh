#!/bin/sh

die() {
	echo "$*" >&2
	exit 1
}

[ -s "./chosen_board.mk" ] || die "please run ./configure first."

set -e

. ./chosen_board.mk

K_PATH="linux-sunxi"
U_O_PATH="build/$UBOOT_CONFIG-u-boot"
K_O_PATH="build/$KERNEL_CONFIG-linux"
HWPACK_DIR="build/${BOARD}_hwpack"

ABI=armhf

cp_debian_files() {
	local rootfs="$1"
	local cedarxdir="cedarx-libs/libcedarv/linux-$ABI"
	local libtype="x11" # or framebuffer
	local x= y=

	echo "Debian/Ubuntu hwpack"
	cp -r "rootfs/debian-ubuntu"/* "$rootfs/"

	## libs
	install -m 0755 $(find "$cedarxdir" -name '*.so') "$rootfs/lib/"

	## kernel modules
	cp -r "$K_O_PATH/output/lib/modules" "$rootfs/lib/"
	rm -f "$rootfs/lib/modules"/*/source
	rm -f "$rootfs/lib/modules"/*/build

	## bins
	#cp ../../a10-tools/a1x-initramfs.sh ${OUTPUT_DIR}/${BOARD}_hwpack/rootfs/usr/bin
	#chmod 755 ${OUTPUT_DIR}/${BOARD}_hwpack/rootfs/usr/bin/a1x-initramfs.sh
}

cp_header_files() {
	local headers="$1"

	echo "Debian/Ubuntu hwpack (headers)"

	rm -rf $headers
	mkdir -p $headers

	install -D -m644 $K_PATH/Makefile "$headers/Makefile"
	install -D -m644 $K_PATH/kernel/Makefile "$headers/kernel/Makefile"
	install -D -m644 $K_O_PATH/.config "$headers/.config"

	mkdir -p $headers/include
	for i in acpi asm-generic crypto drm linux math-emu media net pcmcia scsi sound trace video xen; do
		cp -a $K_PATH/include/${i} "$headers/include/"
	done
	for i in config generated; do
		cp -a $K_O_PATH/include/${i} "$headers/include/"
	done

	# copy arch includes for external modules
	mkdir -p $headers/arch/arm
	#cp -a $K_O_PATH/arch/arm/include $headers/arch/arm/
	cp -a $K_PATH/arch/arm/include $headers/arch/arm/
	mkdir -p $headers/arch/arm/mach-sun7i
	cp -a $K_PATH/arch/arm/mach-sun7i/include $headers/arch/arm/mach-sun7i/
	mkdir -p $headers/arch/arm/plat-sunxi
	cp -a $K_PATH/arch/arm/plat-sunxi/include $headers/arch/arm/plat-sunxi/

	# copy files necessary for later builds, like nvidia and vmware
	cp $K_O_PATH/Module.symvers "$headers/"
	#cp -a $K_O_PATH/scripts "$headers/"
	cp -a $K_PATH/scripts "$headers/"

	# fix permissions on scripts dir
	chmod og-w -R "$headers/scripts"
	mkdir -p "$headers/.tmp_versions"
	mkdir -p "$headers/arch/arm/kernel"
	cp $K_PATH/arch/arm/Makefile "$headers/arch/arm/"
	cp $K_O_PATH/arch/arm/kernel/asm-offsets.s "$headers/arch/arm/kernel/"

	# add headers for lirc package
	mkdir -p "$headers/drivers/media/video"
	#cp $K_O_PATH/drivers/media/video/*.h  "$headers/drivers/media/video/"
	cp $K_PATH/drivers/media/video/*.h  "$headers/drivers/media/video/"

	for i in bt8xx cpia2 cx25840 cx88 em28xx et61x251 pwc saa7134 sn9c102; do
		mkdir -p "$headers/drivers/media/video/${i}"
		#cp -a $K_O_PATH/drivers/media/video/${i}/*.h "$headers/drivers/media/video/${i}"
		cp -a $K_PATH/drivers/media/video/${i}/*.h "$headers/drivers/media/video/${i}"
	done

	# add docbook makefile
	install -D -m644 $K_PATH/Documentation/DocBook/Makefile "$headers/Documentation/DocBook/Makefile"

	# add dm headers
	mkdir -p "$headers/drivers/md"
	cp $K_PATH/drivers/md/*.h "$headers/drivers/md"

	# add inotify.h
	mkdir -p "$headers/include/linux"
	cp $K_PATH/include/linux/inotify.h "$headers/include/linux/"

	# add wireless headers
	mkdir -p "$headers/net/mac80211/"
	cp $K_PATH/net/mac80211/*.h "$headers/net/mac80211/"

	# add dvb headers for external modules
	# in reference to:
	# http://bugs.archlinux.org/task/9912
	mkdir -p "$headers/drivers/media/dvb/dvb-core"
	cp $K_PATH/drivers/media/dvb/dvb-core/*.h "$headers/drivers/media/dvb/dvb-core/"
	# and...
	# http://bugs.archlinux.org/task/11194
	mkdir -p "$headers/include/config/dvb/"
	cp $K_O_PATH/include/config/dvb/*.h "$headers/include/config/dvb/"

	# add dvb headers for http://mcentral.de/hg/~mrec/em28xx-new
	# in reference to:
	# http://bugs.archlinux.org/task/13146
	mkdir -p "$headers/drivers/media/dvb/frontends/"
	cp $K_PATH/drivers/media/dvb/frontends/lgdt330x.h "$headers/drivers/media/dvb/frontends/"
	cp $K_PATH/drivers/media/video/msp3400-driver.h "$headers/drivers/media/dvb/frontends/"

	# add dvb headers
	# in reference to:
	# http://bugs.archlinux.org/task/20402
	mkdir -p "$headers/drivers/media/dvb/dvb-usb"
	cp $K_PATH/drivers/media/dvb/dvb-usb/*.h "$headers/drivers/media/dvb/dvb-usb/"
	mkdir -p "$headers/drivers/media/dvb/frontends"
	cp $K_PATH/drivers/media/dvb/frontends/*.h "$headers/drivers/media/dvb/frontends/"
	mkdir -p "$headers/drivers/media/common/tuners"
	cp $K_PATH/drivers/media/common/tuners/*.h "$headers/drivers/media/common/tuners/"

	# add xfs and shmem for aufs building
	mkdir -p "$headers/fs/xfs"
	mkdir -p "$headers/mm"
	cp $K_PATH/fs/xfs/xfs_sb.h "$headers/fs/xfs/xfs_sb.h"

	# copy in Kconfig files
	local prevdir=`pwd`
	cd $K_PATH
	for i in `find . -name "Kconfig*"`; do
		mkdir -p "$prevdir/$headers/`echo ${i} | sed 's|/Kconfig.*||'`"
		cp ${i} "$prevdir/$headers/${i}"
	done
	cd $prevdir

	find "$headers" -type d -exec chmod 755 {} \;

	# strip scripts directory
	find "$headers/scripts" -type f -perm -u+w 2>/dev/null | while read binary ; do
		case "$(file -bi "${binary}")" in
			*application/x-sharedlib*) # Libraries (.so)
				/usr/bin/strip --strip-unneeded "${binary}";;
			*application/x-archive*) # Libraries (.a)
				/usr/bin/strip --strip-debug "${binary}";;
			*application/x-executable*) # Binaries
				/usr/bin/strip --strip-all "${binary}";;
		esac
	done

	# remove unneeded architectures
	rm -rf "$headers"/arch/{alpha,arm26,avr32,blackfin,cris,frv,h8300,ia64,m32r,m68k,m68knommu,mips,microblaze,mn10300,parisc,powerpc,ppc,s390,sh,sh64,sparc,sparc64,um,v850,x86,xtensa}
}

cp_android_files() {
	local rootfs="$1" f=

	echo "Android hwpack"

	mkdir -p "${rootfs}/boot"
	## kernel
	cp -r "$K_O_PATH"/arch/arm/boot/uImage "${rootfs}/boot/"
	cp -r "build/$BOARD.bin" "${rootfs}/boot/script.bin"

	## kernel modules
	mkdir -p "$rootfs/system/lib/modules"
	find "$K_O_PATH/output/lib/modules" -name "*.ko"  -print0 |xargs -0 cp -t "$rootfs/system/lib/modules/"

	## boot scripts (optional)
	for f in boot.scr uEnv.txt; do
		if [ -s "build/$f" ]; then
			cp "build/$f" "$rootfs/boot/"
		fi
	done
}

create_hwpack() {
	local hwpack="$1"
	local rootfs="$HWPACK_DIR/rootfs"
	local headers="$HWPACK_DIR/headers"
	local kerneldir="$HWPACK_DIR/kernel"
	local bootloader="$HWPACK_DIR/bootloader"
	local f=

	rm -rf "$HWPACK_DIR"

	mkdir -p "$rootfs/usr/bin" "$rootfs/lib"

	if [ -z "$ANDROID" ]; then
		cp_debian_files "$rootfs"
		cp_header_files "$headers"
	else
		cp_android_files "$rootfs"
	fi

	## kernel
	mkdir -p "$kerneldir"
	cp -r "$K_O_PATH"/arch/arm/boot/uImage "$kerneldir/"
	cp -r "build/$BOARD.bin" "$kerneldir/script.bin"

	## boot scripts (optional)
	for f in boot.scr uEnv.txt; do
		if [ -s "build/$f" ]; then
			cp "build/$f" "$kerneldir/"
		fi
	done

	## bootloader
	mkdir -p "$bootloader"
	cp -r "$U_O_PATH/u-boot-sunxi-with-spl.bin" "$bootloader/"
	cp -r "$U_O_PATH/spl/sunxi-spl.bin" "$bootloader/"
	cp -r "$U_O_PATH/u-boot.bin" "$bootloader/"
	cp -r "$U_O_PATH/u-boot.img" "$bootloader/"

	## compress hwpack
	cd "$HWPACK_DIR"
	case "$hwpack" in
	*.7z)
		7z u -up1q0r2x1y2z1w2 -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "$hwpack" .
		;;
	*.tar.bz2)
		find . ! -type d | cut -c3- | sort -V | tar -jcf "$hwpack" -T -
		;;
	*.tar.xz)
		find . ! -type d | cut -c3- | sort -V | tar -Jcf "$hwpack" -T -
		;;
	*)
		die "Not supported hwpack format"
		;;
	esac
	cd - > /dev/null
	echo "Done."
}

[ $# -eq 1 ] || die "Usage: $0 <hwpack.7z>"

create_hwpack "$1"

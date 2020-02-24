#!/bin/sh

# Script to check if your xorg configuration has
# a chance to work (FreeBSD 12.1 + xorg >= 1.20.7 + UDEV/evdev)
#
# This is hacky as f
# (c) 2020 Michael Gmelin

ME=$0
REQUIRED_PACKAGES="\
	xf86-input-libinput:0.28.2_1\
	xf86-input-evdev:2.10.6_5\
	xorg-server:1.20.7\
	libudev-devd:0.4.1\
	libepoll-shim:0.0.20200212\
	libevdev:1.5.9_1
	libinput:1.15.2\
"

SHOW_INFO=1
SKIP_DRM=0
SKIP_VERSION_CHECKS=0

die()
{
	echo "Error: $@" 1>&2
	echo "Please fix and re-run $ME"
	exit 1;
}

info()
{
	if [ $SHOW_INFO -eq 1 ]; then
		echo "Info: $@"
		echo "-- run $ME -i to suppress info messages"
	fi
}

usage()
{
	echo "Usage: $ME [-hdpi]"
	echo "   -h print this help"
	echo "   -d skip drm checks"
	echo "   -p skip package version checks"
	echo "   -i only show errors (suppress info)"
	exit 0
}

finished()
{
	echo "Done - All checks passed"
	exit 0
}

while getopts "hdpi" _o; do
	case "$_o" in
	h)
		usage
		;;
	d)
		SKIP_DRM=1
		;;
	p)
		SKIP_VERSION_CHECKS=1
		;;
	i)
		SHOW_INFO=0
		;;
	esac
done


# check if kernel supports evdev
sysctl -qn kern.evdev.rcpt_mask >/dev/null || die "
Your kernel doesn't support evdev.

Recompile kernel with evdev support:
options         EVDEV_SUPPORT           # evdev support in legacy drivers
device          evdev                   # input event device support
device          uinput                  # install /dev/uinput cdev
"

# check if kern.evdev.rcpt_mask isn't set properly
case $(sysctl -qn kern.evdev.rcpt_mask) in
	12) info "kern.evdev.rcpt_mask is set to 12.

You might consider setting it to 6 in case of problems
(which will change keyboard events to go to kbdmux)"
		;;
	6) info "kern.evdev.rcpt_mask is set to 6.

You might consider setting it to 12 in case of problems
(which will change keyboard events to go to hardware)"
		;;
	*) die "
kern.evdev.rcpt_mask is misconfigured.

It is a bitmask that defines what is receiving events:

  bit0 - sysmouse,
  bit1 - kbdmux,
  bit2 - mouse hardware,
  bit3 - keyboard hardware

Please set to 12 or 6 using one of the following commands:
sysctl kern.evdev.rcpt_mask=12
or
sysctl kern.evdev.rcpt_mask=6

You can set it automatically on reboot by issuing the
following commands:
echo kern.evdev.rcpt_mask=12 >>/etc/sysctl.conf
or
echo kern.evdev.rcpt_mask=6 >>/etc/sysctl.conf
"
		;;
esac

# Check if synaptics touchpad is enabled (only relevant on some laptops)
case $(sysctl -qn hw.psm.synaptics_support) in
	1)	;;
	*) info "Synaptics support isn't enabled.

This is only relevant if you use a synapctics touchpad.
You can enable synaptics support using these commands:

echo hw.psm.synaptics_support=1 >>/boot/loader.conf
reboot
"
		;;
esac

# Check if trackpoint is enabled (only relevant on some laptops)
case $(sysctl -qn hw.psm.trackpoint_support) in
	1)	;;
	*) info "Trackpoint support isn't enabled.

This is only relevant if you use a trackpoint, like the
ones found in Lenovo laptops. Needs to be enabled
to support features like middle mouse button support
(e.g. to paste or to support middle-click+trackpoint
to scroll).

You can enable trackpoint support using these commands:

echo hw.psm.trackpoint_support=1 >>/boot/loader.conf
reboot
"
		;;
esac

# Check if required packages are installed
for PKGNAME_V in $REQUIRED_PACKAGES; do
	PKGNAME=$(echo $PKGNAME_V | awk -F\: '{ print $1 }')
	pkg query %v $PKGNAME >/dev/null || die "$PKGNAME is not installed.

Please install package $PKGNAME using

pkg install $PKGNAME
";
done

# Check if required package versions are installed
if [ $SKIP_VERSION_CHECKS -eq 0 ]; then
	for PKGNAME_V in $REQUIRED_PACKAGES; do
		PKGNAME=$(echo $PKGNAME_V | awk -F\: '{ print $1 }')
		PKGVERSION=$(echo $PKGNAME_V | awk -F\: '{ print $2 }')
		case `(printf $(pkg query %v $PKGNAME)".0\n"; \
			echo $PKGVERSION) | sort -V | tail -n1` in
			$PKGVERSION)
					die "$PKGNAME outdated.
					
Please update to version $PKGVERSION of $PKGNAME.

Your can disable this check by running

$ME -p
"
					;;
			*)
					;;
		esac
	done
fi

# Check if xorg-server is UDEV enabled
case $(pkg query %Ok=%Ov xorg-server | grep UDEV) in
	UDEV=on)	;;
	*) die "xorg-server built without UDEV support.
	
Please reinstall or rebuild from ports with option
UDEV enabled
"
esac

# Check if user has existing xorg.conf files
for CONF in /etc/X11/xorg.conf /usr/local/etc/X11/xorg.conf; do
	if [ -e $CONF ]; then
		die "Found existing configuration $CONF
	
Please move it out of the way, as having these
tends to mess with proper autodetection.

If you still need some bits from it after testing Xorg
successfully, please add them as individual files
in /usr/local/etc/X11/xorg.conf.d/
"
	fi
done

# Check if xf86-inut-synaptics is installed (it shouldn't be there)
pkg query %v xf86-input-synaptics >/dev/null && die "\
xf86-input-synaptics is installed.

This can interfere with xf86-input-libinput, please remove using

pkg delete xf86-input-synaptics
"

# Check if hald is enabled
case $(sysrc -n hald_enable 2>&1) in
	[Yy][Ee][Ss])
		info "hald is enabled.

FreeBSD's xorg-server doesn't support the HAL
backend anymore.

You might consider disabling it using

service hald stop
sysrc hald_enable=NO
"
		;;
	*)
		;;
esac

# Check if moused is running
pgrep moused >/dev/null && die "moused is running

Please stop moused.

You can disable moused permanently by running:

sysrc moused_nondefault_enable=NO
sysrc moused_enable=NO
"

# done here if drm checks are skipped
if [ $SKIP_DRM -eq 1 ]; then
  finished
fi


######################################################
### DRM CHECKS (not comprehensive)

# check if DRM package is installed
pkg query %v drm-kmod >/dev/null || die "drm-kmod isn't installed

Please install from ports or as a package using

pkg install drm-kmod
"

# Check if kernel exists (I know...)
if [ ! -e "/boot/kernel/kernel" ]; then
	die "Kernel doesn't exist (huh?)"
fi

# Check if files from drm-kmod are present (ignoring radeon here)
if [ ! -e "/boot/modules/i915kms.ko" ]; then
	die "It seems like files from drm-kmod are missing
	
Please reinstall drm-kmod using
pkg install -f drm-kmod
"
fi


# Check if kernel is newer than DRM kernel modules (primitive check)
if [ "/boot/kernel/kernel" -nt "/boot/modules/i915kms.ko" ]; then
	die "Your kernel is newer than the installed version of drm-kmod
	
Please update drm-kmod using pkg or reinstall from ports (make
sure to update your ports tree, make clean and remove all
packages named drm-fbsd*-kmod first)
"
fi

# Check if i915kms or radeonkms are configured in loader.conf (they shouldn't)
sysrc -f /boot/loader.conf i915kms_load >/dev/null 2>&1 && die "\
i915kms_load is configured in /boot/loader.conf

Please remove it from there and use kld_list in /etc/rc.conf instead.
"

# Check if radeonkms or radeonkms are configured in loader.conf (they shouldn't)
sysrc -f /boot/loader.conf radeonkms_load >/dev/null 2>&1 && die "\
radeonkms_load is configured in /boot/loader.conf

Please remove it from there and use kld_list in /etc/rc.conf instead.
"

# Check drm modules are loaded
kldstat -m i915kms >/dev/null 2>&1
i915_loaded=$?
kldstat -m radeonkms >/dev/null 2>&1
radeon_loaded=$?

if [ $i915_loaded -ne 0 ] && [ $radeon_loaded -ne 0 ]; then
	die "Neither i915kms nor radeonkms is loaded.
	
Please load using

kldload i915kms
or
kldload radeonkms

You can load one of these drivers automatically on
boot by adding it to kld_list in rc.conf:

sysrc kld_list+=/boot/modules/i915kms.ko
or
sysrc kld_list+=/boot/modules/radeonkms.ko
"
fi

# Check if graphics driver is installed
# (only intel, modesetting sometimes has issues)
pkg query %v xf86-video-intel >/dev/null || info "xf86-video-intel isn't installed

Consider installing it in case you encounter problems with
the modesetting driver (tearing)
"

### DRM END

finished

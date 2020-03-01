#!/bin/sh

# Script to check if your xorg configuration has
# a chance to work (FreeBSD 12.1 + xorg >= 1.20.7 + UDEV/evdev)
#
# This is hacky as f
# (c) 2020 Michael Gmelin

ME=$0
ARGS="$@"
REQUIRED_PACKAGES="\
	xf86-input-libinput:0.28.2_1\
	xf86-input-evdev:2.10.6_5\
	xorg-server:1.20.7\
	libudev-devd:0.4.1\
	libepoll-shim:0.0.20200212\
	libevdev:1.5.9_1
	libinput:1.15.2\
"
OPTIONAL_PACKAGES="\
	xf86-video-scfb:0.0.5_2\
"
EXPECTED_CONFIG_FILES="\
	/usr/local/share/X11/xorg.conf.d/10-evdev.conf
	/usr/local/share/X11/xorg.conf.d/10-quirks.conf
	/usr/local/share/X11/xorg.conf.d/20-evdev-kbd.conf
	/usr/local/share/X11/xorg.conf.d/40-libinput.conf
"

SHOW_INFO=1
SEEN_INFO=0
SKIP_DRM=0
SKIP_VERSION_CHECKS=0
SKIP_FILE_CHECKS=0
NO_COLORS=0
VERBOSE=0
GATHER_EVIDENCE=0
USE_SUDO=0
EVIDENCE=""
KEEP_GOING=0
TPUT=/usr/bin/tput
ERRORS=0

add_evidence()
{
	if [ $GATHER_EVIDENCE -eq 1 ]; then
		EVIDENCE="$EVIDENCE"$'\n'"$@"
	fi
}

new_evidence()
{
	add_evidence $'\n'"$@:"
	if [ $VERBOSE -eq 1 ]; then
		echo "${blue}${bold}Gathering: $@${normal}"
	fi
}

fatal()
{
	echo "${bold}${red}Fatal: $@${normal}"
	exit 1
}

gather_evidence()
{
	if [ $GATHER_EVIDENCE -ne 1 ]; then
		return
	fi

	new_evidence "uname"
	add_evidence "$(uname -a 2>&1)"
	new_evidence "FreeBSD version (installed/running/userland)"
	add_evidence "$(freebsd-version -kru 2>&1)"
	new_evidence "Config Files"
	add_evidence "$(find -s \
			/etc/X11 /usr/local/etc/X11 \
	                /usr/local/share/X11/xorg.conf.d \
	                2>&1)"
	new_evidence "Config Contents"
	for CONF in $(find -s \
	              /boot/loader.conf \
	              /etc/rc.conf \
	              /etc/sysctl.conf \
	              /etc/X11 \
	              /usr/local/etc/X11/xorg.conf.d \
		      /usr/local/share/X11/xorg.conf.d \
		      -name "*.conf"); do
		new_evidence "$CONF"
		add_evidence "$(cat $CONF 2>&1)"
	done
	for category in x11-drivers x11-servers x11-wm; do
		new_evidence "Installed ${category} packages"
		add_evidence \
		"$(pkg query -g -e "%o ~ '${category}/*'" %n-%v 2>&1)"
	done
	new_evidence "PCI config"
	add_evidence "$(pciconf -lv 2>&1)"
	new_evidence "xinput devices"
	add_evidence "$(xinput list 2>&1)"
	new_evidence "xinput devices (long)"
	add_evidence "$(xinput list --long 2>&1)"
	for ID in $(xinput list --id-only 2>/dev/null); do
		new_evidence "xinput device id $ID properties"
		add_evidence "$(xinput list-props $ID)"
	done

	# libinput usually requires root access to read /dev/input/event*
	sudo=""
	if [ "$(id -u)" -ne 0 ] && [ $USE_SUDO -eq 1 ] ; then
		sudo="sudo "
	fi
	new_evidence "libinput list-devices"
	add_evidence "$(${sudo}libinput list-devices 2>&1)"

	LATEST_XLOG="$(ls -t /var/log/Xorg.*.log 2>/dev/null | head -n1)"
	if [ ! -z "$LATEST_XLOG" ]; then
		new_evidence "First 1000 lines of ${LATEST_XLOG}"
		add_evidence "$(head -n 1000 $LATEST_XLOG)"
	fi

	# done collecting, write to file
	TEMPFILE=$(mktemp -t xorg-evidence) || fatal "Couldn't write evidence file"
	echo "xorg evidence collected on $(hostname)" >$TEMPFILE
	echo "Date: $(date)" >>$TEMPFILE
	echo "Command: ${ME} ${ARGS}" >>$TEMPFILE
	echo >>$TEMPFILE
	echo "$EVIDENCE" >>$TEMPFILE

	echo "
${magenta}${bold}Gathered evidence was written to $TEMPFILE${normal}

${magenta}This file can be used to get help & when filing a bug reports at
https://bugs.freebsd.org/bugzilla/enter_bug.cgi

Please make sure that you're comfortable with the content of that
file ${bold}before${normal}${magenta} sharing/uploading it:

${bold}${PAGER} $TEMPFILE${normal}
"

}

TEST()
{
	if [ $VERBOSE -eq 1 ]; then
		echo "${blue}${bold}$@${normal}"
	fi
	add_evidence "$@"
}

info()
{
	if [ $SHOW_INFO -eq 1 ]; then
		title=$(echo "$@" | head -n 1)
		body=$(echo "$@" | tail -n +2)
		echo "${cyan}${bold}Info:${normal} ${bold}${title}${normal}"
		echo "${body}"
		echo
		SEEN_INFO=1
	fi
	add_evidence "Info: $@"
}

seen_info_note()
{
	if [ $SEEN_INFO -eq 1 ]; then
		printf -- "${cyan}>> To suppress ${cyan}info messages, "
		echo "run ${ME} -i ${ARGS}${normal}"
		echo
	fi
}

die()
{
	if [ $KEEP_GOING -eq 0 ]; then
		seen_info_note
	fi
	title=$(echo "$@" | head -n 1)
	body=$(echo "$@" | tail -n +2)
	echo "${red}${bold}Error:${normal} ${bold}${title}${normal}" 1>&2
	echo "${body}" 1>&2
	echo
	add_evidence "Error: $@"
	if [ $KEEP_GOING -eq 0 ]; then
		echo "${bold}Please fix and re-run ${ME} ${ARGS}${normal}"
		gather_evidence
		exit 1;
	fi
	echo "${bold}Keep going - check results might be inaccurate${normal}"
	echo
	ERRORS=$((ERRORS+1))
}

finished()
{
	seen_info_note
	if [ $ERRORS -eq 0 ]; then
		printf "${bold}${green}Done:${normal} "
		echo "${bold}All checks passed${normal}"
	else
		echo "${red}${bold}Found ${ERRORS} error(s) in setup${normal}"
	fi
	gather_evidence
	exit $ERRORS
}

usage()
{
	echo "Usage: ${ME} [-hdpicvesfk]"
	echo "   -h print this help"
	echo "   -d skip drm checks"
	echo "   -p skip package version checks"
	echo "   -i only show errors (suppress info)"
	echo "   -c no colors"
	echo "   -v verbose"
	echo "   -e gather evidence"
	echo "   -s use sudo for some evidence as non-root user"
	echo "   -f skip file checks"
	echo "   -k keep going, do not stop on error"
	exit 0
}

while getopts "hdpicvesfk" _o; do
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
	c)
		NO_COLORS=1
		;;
	v)
		VERBOSE=1
		;;
	e)
		GATHER_EVIDENCE=1
		;;
	s)
		USE_SUDO=1
		;;
	f)
		SKIP_FILE_CHECKS=1
		;;
	k)
		KEEP_GOING=1
		;;
	esac
done

if [ $NO_COLORS -eq 0 ]; then
	if test -t 1; then
		ncol=$($TPUT colors)
		if test -n "$ncol" && test $ncol -ge 8; then
			bold="$($TPUT md)"
			normal="$($TPUT me)"

			red="$($TPUT AF 1)"
			green="$($TPUT AF 2)"
			blue="$($TPUT AF 4)"
			magenta="$($TPUT AF 5)"
			cyan="$($TPUT AF 6)"
		fi
	fi
fi

TEST "Check if kernel supports evdev"
sysctl -qn kern.evdev.rcpt_mask >/dev/null || die "\
Your kernel doesn't support evdev.

Recompile kernel with evdev support:
options         EVDEV_SUPPORT           # evdev support in legacy drivers
device          evdev                   # input event device support
device          uinput                  # install /dev/uinput cdev
"

TEST "Check if kern.evdev.rcpt_mask is set properly"
case $(sysctl -qn kern.evdev.rcpt_mask) in
	12) info "kern.evdev.rcpt_mask is set to 12.
You might consider setting it to 6 in case of problems
(which will change keyboard events to go to kbdmux)"
		;;
	6) info "kern.evdev.rcpt_mask is set to 6.
You might consider setting it to 12 in case of problems
(which will change keyboard events to go to hardware)"
		;;
	*) die "\
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

TEST "Check if synaptics touchpad is enabled (only relevant on some laptops)"
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

TEST "Check if trackpoint is enabled (only relevant on some laptops)"
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

TEST "Check if required packages are installed"
for PKGNAME_V in $REQUIRED_PACKAGES; do
	PKGNAME=$(echo $PKGNAME_V | awk -F\: '{ print $1 }')
	pkg query %v $PKGNAME >/dev/null || die "$PKGNAME is not installed.
Please install package $PKGNAME using

pkg install $PKGNAME
";
done

if [ $SKIP_VERSION_CHECKS -eq 0 ]; then
	TEST "Check if required package versions are installed"
	for PKGNAME_V in $REQUIRED_PACKAGES; do
		PKGNAME=$(echo $PKGNAME_V | awk -F\: '{ print $1 }')
		PKGVERSION=$(echo $PKGNAME_V | awk -F\: '{ print $2 }')
		case `(printf $(pkg query %v $PKGNAME)".0\n"; \
			echo $PKGVERSION) | sort -V | tail -n1` in
			$PKGVERSION)
					die "$PKGNAME is outdated.
Please update to version $PKGVERSION or higher of $PKGNAME.

You can disable this check by running

${ME} -p ${ARGS}
"
					;;
			*)
					;;
		esac
	done

	TEST "Check if optional packages have required versions"
	for PKGNAME_V in $OPTIONAL_PACKAGES; do
		PKGNAME=$(echo $PKGNAME_V | awk -F\: '{ print $1 }')
		PKGVERSION=$(echo $PKGNAME_V | awk -F\: '{ print $2 }')
		pkg query %v $PKGNAME >/dev/null &&
		case `(printf $(pkg query %v $PKGNAME)".0\n"; \
			echo $PKGVERSION) | sort -V | tail -n1` in
			$PKGVERSION)
					die "$PKGNAME is outdated.
Please update to version $PKGVERSION or higher of $PKGNAME.

You can disable this check by running

${ME} -p ${ARGS}
"
					;;
			*)
					;;
		esac
	done
fi

TEST "Check if xorg-server is UDEV enabled"
case $(pkg query %Ok=%Ov xorg-server | grep UDEV) in
	UDEV=on)	;;
	*) die "xorg-server built without UDEV support.
Please reinstall or rebuild from ports with option
UDEV enabled
"
esac

if [ $SKIP_FILE_CHECKS -eq 0 ]; then
	TEST "Check if user had custom configuration"
	FILES=$(find -s /usr/local/etc/X11/xorg.conf.d -name "*.conf" -type f)
	if [ ! -z "$FILES" ]; then
		info "Found custom configuration files
The following custom configuration file(s) exist,
please make sure their contents are sane:

${FILES}

You can disable this check by running

${ME} -f ${ARGS}
"
	fi

	TEST "Check if user has existing xorg.conf files"
	for CONF in /etc/X11/xorg.conf /usr/local/etc/X11/xorg.conf; do
		if [ -e $CONF ]; then
			die "Found existing configuration $CONF
Please move it out of the way, as having these
tends to mess with proper autodetection.

If you still need some bits from it after testing Xorg
successfully, please add them as individual files
in /usr/local/etc/X11/xorg.conf.d/

You can disable this check by running

${ME} -f ${ARGS}
"
		fi
	done

	TEST "Check for expected X11 configuration files"
	for CONF in $EXPECTED_CONFIG_FILES; do
		if [ ! -e $CONF ]; then
			die "Config $CONF not found.
A clean installation is expected to have this file
installed.

You can disable this check by running

${ME} -f ${ARGS}
"
		fi
	done
fi

TEST "Check if xf86-input-synaptics is installed (it shouldn't be)"
pkg query %v xf86-input-synaptics >/dev/null && die "\
xf86-input-synaptics is installed.
This can interfere with xf86-input-libinput, please remove using

pkg delete xf86-input-synaptics
"

TEST "Check if hald is enabled"
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

TEST "Check if moused is running"
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

info "You're running DRM checks.
These are only relevant if your system uses a graphics
adapter that is supported by drm-kmod (i915kms and radeonkms).

To skip DRM checks, run ${ME} -d ${ARGS}
"

TEST "Check if DRM package is installed"
pkg query %v drm-kmod >/dev/null || die "drm-kmod isn't installed
Please install from ports or as a package using

pkg install drm-kmod
"

TEST "Check if kernel exists (I know...)"
if [ ! -e "/boot/kernel/kernel" ]; then
	die "Kernel doesn't exist (huh?)"
fi

TEST "Check if files from drm-kmod are present (ignoring radeon here)"
if [ ! -e "/boot/modules/i915kms.ko" ]; then
	die "It seems like files from drm-kmod are missing
Please reinstall drm-kmod using
pkg install -f drm-kmod
"
fi

TEST "Check if kernel is newer than DRM kernel modules (primitive check)"
if [ "/boot/kernel/kernel" -nt "/boot/modules/i915kms.ko" ]; then
	die "Your kernel is newer than the installed version of drm-kmod
Please update drm-kmod using pkg or reinstall from ports (make
sure to update your ports tree, make clean and remove all
packages named drm-fbsd*-kmod first)
"
fi

TEST "Check if i915kms is configured in loader.conf (it shouldn't be)"
sysrc -f /boot/loader.conf i915kms_load >/dev/null 2>&1 && die "\
i915kms_load is configured in /boot/loader.conf
Please remove it from there and use kld_list in /etc/rc.conf instead.
"

TEST "Check if radeonkms is configured in loader.conf (it shouldn't be)"
sysrc -f /boot/loader.conf radeonkms_load >/dev/null 2>&1 && die "\
radeonkms_load is configured in /boot/loader.conf
Please remove it from there and use kld_list in /etc/rc.conf instead.
"

TEST "Check if drm modules are loaded"
kldstat -m i915kms >/dev/null 2>&1
i915kms_loaded=$?
kldstat -m radeonkms >/dev/null 2>&1
radeonkms_loaded=$?

if [ $i915kms_loaded -ne 0 ] && [ $radeonkms_loaded -ne 0 ]; then
	die "Neither i915kms nor radeonkms is loaded.
Please load using

kldload /boot/modules/i915kms.ko
or
kldload /boot/modules/radeonkms.ko

You can load one of these drivers automatically on
boot by adding it to kld_list in rc.conf:

sysrc kld_list+=/boot/modules/i915kms.ko
or
sysrc kld_list+=/boot/modules/radeonkms.ko
"
fi

for MOD in i915kms radeonkms; do
	eval LOADED=\$${MOD}_loaded
	if [ $LOADED -eq 0 ]; then
		TEST "Check ${MOD} is configured to load in /etc/rc.conf"
		sysrc kld_list 2>/dev/null | tr " " "\n" | \
		  egrep -q "^/boot/modules/${MOD}\.ko$" || info "\
${MOD} currently loaded, but not configured to load on boot.
Once you verified that it can be loaded successfully,
enable automatic loading on boot by adding it to
kld_list in rc.conf:

sysrc kld_list+=/boot/modules/${MOD}.ko
"
	fi
done

# testing for intel here, modesetting has sometimes issues
TEST "Check if graphics driver is installed (only intel)"
pkg query %v xf86-video-intel >/dev/null || info "\
xf86-video-intel isn't installed
Consider installing it in case you have an intel graphics
adapter and encounter problems with the modesetting driver
(e.g. tearing)
"

### DRM END

finished

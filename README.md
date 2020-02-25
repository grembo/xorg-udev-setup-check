# xorg-udev-setup-check

xorg-udev-setup-check.sh is a little script that is supposed to help find
configuration problems in your xorg-server setup on FreeBSD after updating
to xorg-server 1.20.7
(see https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=196678)

This script won't change anything on your system, but aims to point you to
potential setup issues (some depend on your specific setup, so not every
recommendation might apply).

You should be able to run the script using an unprivileged user.

It assumes you're running (at least) FreeBSD 12.1-RELEASE. It might work on
11.3-RELEASE, but this hasn't been tested.

Usage:

    ./xorg-udev-setup-check.sh [-hdpicvesfk]
       -h print this help
       -d skip drm checks
       -p skip package version checks
       -i only show errors (suppress info)
       -c no colors
       -v verbose
       -e gather evidence
       -s use sudo for some evidence as non-root user
       -f skip file checks
       -k keep going, do not stop on error

## How to check your setup

Simply invoke the script without any parameters. By default, this will you
hints ("Info:") and stop at the first hard error.

Some checks can be skipped (see above). The script will also tell you which
option to use to skip a check that failed.

By passing `-k` (keep going) to the script, you can see all errors at once.
When using this feature, some errors you see might be the result of previous
errors though.

In case your graphics adapter isn't supported by *graphics/drm-kmod*, you
might want to pass option `-d` to skip checks related to that.

## How to seek help

1. Run ./xorg-udev-setup-check.sh and fix all errors it reports.
2. If your problem persists, please consider recommendations given
   by the script ("Info:").
3. If your problem still persists, write to the x11@FreeBSD.org mailing
   list or open a bug report at https://bugs.freebsd.org
4. To help others to help you, please collect evidence
   (read: configurations and logs) on your system. This can
   be done automatically by passing option `-e` to
   the script.
5. Share evidence with those trying to help you.

## How collecting evidence works

`./xorg-udev-setup-check.sh -e` puts the content of various config files,
log files, and the output of some commands to analyze your setup into one
temporary file.

That file is meant to be shared manually, which gives you a chance to check
its content to make sure it doesn't contain anything you're not comfortable
sharing.

The script will give you instructions.

In case you're interested in seeing what's going on, make use of option
`-v`.

For best results (and if possible), please collect evindence
with X running (information on xinput devices can't be collected
otherwise). When accessing the machine in question over ssh,
make sure to set DISPLAY correctly, e.g.
`DISPLAY=:0 ./xorg-udev-setup-check.sh -e`.

In case collecting evidence requires root privileges (e.g. getting
libinput devices), you have three options:

1. Do nothing and therefore don't include that information.
2. Run the entire script as root.
3. Pass option `-s` to the script. This will use *sudo*
   where required (recommended).

Example:

    ./xorg-udev-setup-check.sh -eskv

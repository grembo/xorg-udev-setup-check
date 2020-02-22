xorg-udev-setup-check
---------------------

xorg-udev-setup-check.sh is a little script that is supposed to help
find configuration problems in your xorg-server setup on
FreeBSD after updating to xorg-server 1.20.7
(see https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=196678)

This script won't change anything on your system, but aims
to point you to potential setup issues (some depend
on your specific setup, so not every recommendation might
apply).

You should be able to run the script using an unprivileged
user.

It assumes you're running (at least) FreeBSD 12.1-RELEASE.
It might work on 11.3-RELEASE, but this hasn't been tested.

Usage:

    ./xorg-udev-setup-check.sh [-hdq]
       -h print this help
       -d skip drm checks
       -p skip package version checks
       -i only show errors (suppress info)

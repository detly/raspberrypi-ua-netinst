#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC1091

set -e # exit if any command fails

# Set defaults for configurable behavior

# Controls production of a bz2-compressed image
compress_bz2=1

# Controls production of an xz-compressed image
compress_xz=1

# Use 'sudo' for commands which require root privileges
use_sudo=0

# If a configuration file exists, import its settings
if [ -r buildroot.conf ]; then
	source <(tr -d "\015" < buildroot.conf)
fi

if [ "$use_sudo" = "1" ]; then
    SUDO=sudo
fi

build_dir=build_dir

version_tag="$(git describe --exact-match --tags HEAD 2> /dev/null || true)"
version_commit="$(git rev-parse --short "@{0}" 2> /dev/null || true)"
if [ -n "${version_tag}" ]; then
	imagename="raspberrypi-ua-netinst-${version_tag}"
elif [ -n "${version_commit}" ]; then
	imagename="raspberrypi-ua-netinst-git-${version_commit}"
else
	imagename="raspberrypi-ua-netinst-$(date +%Y%m%d)"
fi
export imagename

genimage_config=${build_dir}/genimage.cfg

cat >"${genimage_config}" <<EOF
# This configuration file is a template, populated by buildroot.sh.

# The whole-disk image, containing the partition table.
image ${imagename}.img {
    hdimage {
        partition-table-type = mbr
    }
    partition installer {
    	partition-type = "0xb"
    	image = "installer.img"
    }
}

# The first partition, containing the installer.
image installer.img {
	mountpoint = "/"
	size = "128M"
	vfat {
		label = "RPI NETINST"
	}
}
EOF

image=${build_dir}/${imagename}.img

# Prepare
rm -f "${image}"

# Create image
genimage \
	--config "${genimage_config}" \
	--inputpath "${build_dir}" --outputpath "${build_dir}" \
	--tmppath "${build_dir}/tmp" --rootpath "${build_dir}/bootfs"

# Create archives

if [ "$compress_xz" = "1" ]; then
	rm -f "${image}.xz"
	if ! xz -9v --keep "${image}"; then
		# This happens e.g. on Raspberry Pi because xz runs out of memory.
		echo "WARNING: Could not create '${IMG}.xz' variant." >&2
	fi
	rm -f "${imagename}.img.xz"
	mv "${image}.xz" ./
fi

if [ "$compress_bz2" = "1" ]; then
	rm -f "${imagename}.img.bz2"
	( bzip2 -9v > "${imagename}.img.bz2" ) < "${image}"
fi

# Cleanup

if [ "$compress_xz" = "1" ] || [ "$compress_bz2" = "1" ]; then
	rm -f "${image}"
fi

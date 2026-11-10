#!/bin/sh
# Build patched libcamera 0.7.0 (library + soft ISP IPA module) for the
# ThinkPad X13s front camera. No root needed.
#
# It rebuilds exactly the Ubuntu package that is installed (0.7.0-1ubuntu2,
# its patches are in patches/ubuntu/) plus the patches in patches/:
#   0001, 0002  AGC fixes backported from libcamera 0.7.2
#   0003        Adjust reads default gamma and contrast from the tuning file
#   0004        AWB statistics skip clipped pixels (fixes green faces outdoors).
#               Changes SwIspStats, so the IPA module from this build works ONLY
#               with the libcamera.so from this build, and vice versa
#   0005        build fix (always generate the rpi vendor controls)
#   0006        AGC reads its MSV target and highlight limit from the tuning file
#
# Output: out/ipa_soft_simple.so and out/lib/libcamera{,-base}.so.0.7.
# Install with ./camera-mode gpu. System files are never touched.
#
# Usage: ./build.sh [workdir]   (default: .work/ in this repo, reused between runs)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
W=${1:-$HERE/.work}
OUT=$HERE/out
TAG=v0.7.0
PKG=0.7.0-1ubuntu2
SYS=$(dpkg-query -W -f='${Version}' libcamera0.7 2>/dev/null || true)
if [ "$SYS" != "$PKG" ]; then
    echo "error: installed libcamera0.7 is '$SYS', this repo is for $PKG." >&2
    echo "pipewire loads this library, so it must match the system package exactly." >&2
    exit 1
fi
MA=$(dpkg-architecture -qDEB_HOST_MULTIARCH)

# Dev headers we don't want to require as installed packages: unpacked from .deb.
mkdir -p "$W"; W=$(cd "$W" && pwd)
cd "$W"
[ -d libcamera ] || git clone --filter=blob:none -q https://gitlab.freedesktop.org/camera/libcamera.git
[ -d ply-3.11 ] || curl -sSL https://files.pythonhosted.org/packages/source/p/ply/ply-3.11.tar.gz | tar xz
[ -d drm ] || { apt-get download libdrm-dev >/dev/null && dpkg -x libdrm-dev_*.deb drm; }
if [ ! -d udev ]; then
    apt-get download libudev-dev >/dev/null && dpkg -x libudev-dev_*.deb udev
    mkdir -p udev/lib udev/pc
    ln -sf "/usr/lib/$MA/libudev.so.1" udev/lib/libudev.so
    printf 'Name: libudev\nDescription: libudev (from .deb)\nVersion: %s\nCflags: -I%s\nLibs: -L%s -ludev\n' \
        "$(dpkg-query -W -f='${Version}' libudev1 | cut -d- -f1)" "$W/udev/usr/include" "$W/udev/lib" > udev/pc/libudev.pc
fi

cd libcamera
git checkout -q -f -B x13s-camera-tuning "$TAG"
git clean -qfdx -e build -e subprojects
while read -r p; do
    [ -n "$p" ] && git apply "$HERE/patches/ubuntu/$p"
done < "$HERE/patches/ubuntu/series"
git -c user.name=build -c user.email=build@localhost commit -qam "Ubuntu $PKG patches"
git -c user.name=build -c user.email=build@localhost am -q "$HERE"/patches/*.patch

rm -rf build
echo "configuring..."
PKG_CONFIG_PATH="$W/udev/pc" PYTHONPATH="$W/ply-3.11" meson setup build \
  --prefix=/usr --libdir="lib/$MA" --libexecdir="libexec/$MA" --sysconfdir=/etc \
  -Dbuildtype=release -Dwerror=false -Dpipelines=simple,uvcvideo -Dipas=simple -Dudev=enabled \
  -Dcam=disabled -Dqcam=disabled -Dgstreamer=disabled -Dv4l2=false -Dpycamera=disabled \
  -Ddocumentation=disabled -Dtest=false -Dlc-compliance=disabled -Dtracing=disabled \
  -Dcpp_args="-I$W/drm/usr/include -I$W/drm/usr/include/libdrm" > "$W/meson-setup.log"
grep -q "SoftISP GPU acceleration *: *true" "$W/meson-setup.log" ||
    { echo "error: GPU soft ISP is not enabled, see $W/meson-setup.log (EGL/GLES headers missing?)" >&2; exit 1; }
echo "building (takes a while)..."
# meson install strips the build-tree RUNPATH. With it, libcamera thinks it is
# not installed and looks for its proxy worker in the build dir.
rm -rf "$W/stage"
PYTHONPATH="$W/ply-3.11" meson install -C build --destdir "$W/stage" --tags runtime >"$W/build.log"
S="$W/stage/usr/lib/$MA"
rm -rf "$OUT"; mkdir -p "$OUT/lib"
cp "$S/libcamera/ipa/ipa_soft_simple.so" "$OUT/"
cp "$S/libcamera.so.0.7.0" "$OUT/lib/libcamera.so.0.7"
cp "$S/libcamera-base.so.0.7.0" "$OUT/lib/libcamera-base.so.0.7"
if readelf -d "$OUT/lib/libcamera.so.0.7" "$OUT/ipa_soft_simple.so" | grep -q RUNPATH; then
    echo "error: RUNPATH left in the built .so files" >&2; exit 1
fi
echo "$PKG $(git log --oneline -1)" > "$OUT/BUILT_FOR"
echo "done: $OUT. Next: ./camera-mode gpu"

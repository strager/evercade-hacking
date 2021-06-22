#!/usr/bin/env bash

# evercade-hacking liberates your Evercade.
# Copyright (C) 2021  Matthew Glazar
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Some commands for building GCC and glibc are based on
# Preshing's work:
# https://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/

set -e
set -u

cd "$(dirname "${0}")"

scripts_dir="${PWD}"
source_dir="${PWD}/build/src"
downloads_dir="${PWD}/build/downloads"

target=arm-linux-gnueabihf
toolchain_prefix="${PWD}/build/usr"
sysroot="${toolchain_prefix}/${target}"

toolchain_ar="${toolchain_prefix}/bin/${target}-ar"
toolchain_cc="${toolchain_prefix}/bin/${target}-gcc"
toolchain_cxx="${toolchain_prefix}/bin/${target}-g++"

default_cflags='-g -O2'
default_cxxflags='-g -O2'

meson_cross_file="${toolchain_prefix}/meson-cross-file.ini"

gcc_target_make_options=(
    CFLAGS_FOR_TARGET="${default_cflags}"
    CXXFLAGS_FOR_TARGET="${default_cxxflags}"
)

make_parallelism="-j$[$(nproc) * 5 / 4]"

build_toolchain=0
build_strace=0
build_libraries=0
build_retroarch=0

main() {
    mkdir -p "${source_dir}"
    cd "${source_dir}"

    parse_arguments "${@}"
    build_stuff
}

parse_arguments() {
    while [ "${#}" -gt 0 ]; do
        case "${1}" in
            -h|--help)
                print_usage
                exit 0
                ;;

            libraries) build_libraries=1 ;;
            retroarch) build_retroarch=1 ;;
            strace)    build_strace=1    ;;
            toolchain) build_toolchain=1 ;;

            *)
                printf 'fatal: unknown option: %s\n' "${1}" >&2
                print_usage >&2
                exit 1
                ;;
        esac
        shift
    done
    if [[ ! ( "${build_toolchain}" -eq 1 || "${build_libraries}" -eq 1 || "${build_retroarch}" -eq 1 || "${build_strace}" -eq 1 ) ]]; then
        printf 'fatal: expected at least one target to build\n' >&2
        print_usage >&2
        exit 1
    fi
}

print_usage() {
    printf 'usage: %s TARGET [TARGET...]\n' "${0}"
    printf '\n'
    printf 'supported targets:\n'
    printf '  - toolchain     C and C++ cross-compiler, linker,\n'
    printf '                  standard library, and debugger\n'
    printf '  - libraries     various libraries needed by RetroArch\n'
    printf '                  (cross-compiled)\n'
    printf '                  (requires toolchain to be built)\n'
    printf '  - retroarch     console emulator (cross-compiled)\n'
    printf '                  (requires toolchain and libraries to be built)\n'
    printf '  - strace        the strace debugging tool\n'
}

build_stuff() {
    if [[ "${build_toolchain}" -eq 1 ]]; then
        (build_meson_cross_file)
        (build_host_wayland)
        (build_linux_headers)
        (build_binutils)
        (build_gcc_1)
        (build_glibc_1)
        (build_gcc_2)
        (build_glibc_2)
        (build_gcc_3)
        (build_gdbserver)
        (build_host_gdb)
    fi

    if [[ "${build_libraries}" -eq 1 ]]; then
        (build_libffi)
        (build_alsa)
        (build_libdrm)
        (build_libxkbcommon)
        (build_wayland_protocols)
        (build_expat)
        (build_wayland)
        (build_zlib)
        (build_mesa3d)
        (build_libcap)
        (build_libmount)
        (build_libudev)
    fi

    if [[ "${build_retroarch}" -eq 1 ]]; then
        (build_retroarch)
    fi

    if [[ "${build_strace}" -eq 1 ]]; then
        (build_strace)
    fi
}

build_meson_cross_file() {
    mkdir -p "$(dirname "${meson_cross_file}")"
    cat >"${meson_cross_file}" <<EOF
[constants]
arch = '${target}'

[binaries]
c = '${toolchain_cc}'
cpp = '${toolchain_cxx}'
strip = '${toolchain_prefix}/bin/${target}-strip'
# TODO(strager): Build pkgconfig ourselves.
pkgconfig = '${target}-pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv7l'
endian = 'little'

[properties]
needs_exe_wrapper = true
# TODO(strager): Set sys_root here instead of setting
# pkgconfig?
EOF
}

build_host_wayland() {
    download https://wayland.freedesktop.org/releases/wayland-1.18.0.tar.xz wayland-1.18.0.tar.xz
    rm -rf wayland-1.18.0
    run tar xf "${downloads_dir}/wayland-1.18.0.tar.xz"

    cd wayland-1.18.0
    run meson builddir-host/ \
        --default-library=static \
        --prefix="${toolchain_prefix}" \
        -Ddocumentation=false \
        -Ddtd_validation=false
    run ninja -C builddir-host
    run ninja -C builddir-host install
}

build_linux_headers() {
    download https://github.com/strager/evercade-linux-kernel/archive/evercade-hacking-dev-4.4a.tar.gz evercade-linux-kernel-evercade-hacking-dev-4.4a.tar.gz
    rm -rf evercade-linux-kernel-evercade-hacking-dev-4.4a
    run tar xf "${downloads_dir}/evercade-linux-kernel-evercade-hacking-dev-4.4a.tar.gz"

    cd evercade-linux-kernel-evercade-hacking-dev-4.4a
    run make headers_install ARCH=arm INSTALL_HDR_PATH="${sysroot}/usr" ${make_parallelism}
}

build_binutils() {
    download https://ftp.gnu.org/gnu/binutils/binutils-2.36.tar.xz binutils-2.36.tar.xz
    rm -rf binutils-2.36 binutils-host-build
    run tar xf "${downloads_dir}/binutils-2.36.tar.xz"
    mkdir binutils-host-build

    cd binutils-host-build
    run ../binutils-2.36/configure \
        --prefix="${toolchain_prefix}" \
        --target="${target}"
    run make ${make_parallelism}
    run make install
}

build_gcc_1() {
    download http://www.netgull.com/gcc/releases/gcc-6.5.0/gcc-6.5.0.tar.xz gcc-6.5.0.tar.xz
    rm -rf gcc-6.5.0 gcc-build
    run tar xf "${downloads_dir}/gcc-6.5.0.tar.xz"
    mkdir gcc-build

    cd gcc-6.5.0
    # TODO(strager): Do this outside so we reuse the
    # downloaded files across clean builds.
    run ./contrib/download_prerequisites
    cd ../gcc-build
    run ../gcc-6.5.0/configure \
        --enable-languages=c++ \
        --prefix="${toolchain_prefix}" \
        --target="${target}" \
        --disable-bootstrap \
        --with-sysroot="${sysroot}" \
        --with-build-sysroot="${sysroot}" \
        --with-native-system-header-dir=/usr/include \
        --with-float=hard
    run make ${make_parallelism} all-gcc "${gcc_target_make_options[@]}"
    run make install-gcc
    # Force future builds of gcc to check if limits.h
    # exists. Otherwise, gcc thinks that the sysroot doesn't
    # have limits.h (because build_glibc_1 hasn't installed
    # it yet) and will use its own limits.h instead.
    run rm gcc/stmp-int-hdrs
}

build_glibc_1() {
    download http://ftp.gnu.org/gnu/glibc/glibc-2.26.tar.xz glibc-2.26.tar.xz
    rm -rf glibc-2.26 glibc-build
    run tar xf "${downloads_dir}/glibc-2.26.tar.xz"

    mkdir glibc-build
    cd glibc-build
    run CC="${toolchain_cc}" \
        CXX="${toolchain_cxx}" \
        CFLAGS="${default_cflags} -Og" \
        CXXFLAGS="${default_cflags} -Og" \
        ../glibc-2.26/configure \
        --prefix=/usr \
        --build="${MACHTYPE}" \
        --host="${target}" \
        --with-headers="${sysroot}/usr/include" \
        --enable-kernel=4.4.159 \
        --disable-werror
    # Build headers for compiling libgcc.
    run make install-bootstrap-headers=yes install-headers DESTDIR="${sysroot}"
    run mkdir -p "${sysroot}/usr/include/gnu"
    run touch "${sysroot}/usr/include/gnu/stubs.h"
    # Build crt .o files for compiling libgcc.
    run make -j4 csu/subdir_lib
    run mkdir -p "${sysroot}/usr/lib"
    run install csu/{crt1,crti,crtn}.o "${sysroot}/usr/lib"
    # Create a stub libc.so for compiling libgcc. We'll
    # replace this with a real libc.so later.
    run "${toolchain_cc}" -nostartfiles -nostdlib -shared -o "${sysroot}/usr/lib/libc.so" -x c /dev/null
}

build_gcc_2() {
    cd gcc-build
    run make ${make_parallelism} all-target-libgcc "${gcc_target_make_options[@]}"
    run make install-target-libgcc
}

build_glibc_2() {
    cd glibc-build
    run make ${make_parallelism}
    run make install DESTDIR="${sysroot}"
}

build_gcc_3() {
    cd gcc-build
    run make ${make_parallelism} "${gcc_target_make_options[@]}"
    run make ${make_parallelism} install
}

# libffi.so.6.0.4
build_libffi() {
    download ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz libffi-3.2.1.tar.gz
    rm -rf libffi-3.2.1
    run tar xf "${downloads_dir}/libffi-3.2.1.tar.gz"

    cd libffi-3.2.1
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    run ./configure \
        --prefix="${sysroot}/usr" \
        --host="${target}" \
        --disable-static \
        --enable-shared
    run make ${make_parallelism}
    run make install
}

# libasound.so.2.0.0
build_alsa() {
    download ftp://ftp.alsa-project.org/pub/lib/alsa-lib-1.2.4.tar.bz2 alsa-lib-1.2.4.tar.bz2
    rm -rf alsa-lib-1.2.4
    run tar xf "${downloads_dir}/alsa-lib-1.2.4.tar.bz2"

    cd alsa-lib-1.2.4
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    run ./configure \
        --prefix="${sysroot}/usr" \
        --host="${target}" \
        --disable-static \
        --enable-shared
    run make ${make_parallelism}
    run make install
}

# libdrm.so.2.4.0, libdrm_rockchip.so.1.0.0
build_libdrm() {
    download https://dri.freedesktop.org/libdrm/libdrm-2.4.104.tar.xz libdrm-2.4.104.tar.xz
    rm -rf libdrm-2.4.104
    run tar xf "${downloads_dir}/libdrm-2.4.104.tar.xz"

    cd libdrm-2.4.104
    
    run CFLAGS="${default_cflags}" \
        CXXFLAGS="${default_cxxflags}" \
        meson builddir/ \
        --cross-file "${meson_cross_file}" \
        --default-library=shared \
        --prefix="${sysroot}/usr" \
        --buildtype=debug
    run ninja -C builddir
    run ninja -C builddir install
}

# libxkbcommon.so.0.0.0
build_libxkbcommon() {
    download https://xkbcommon.org/download/libxkbcommon-1.0.3.tar.xz libxkbcommon-1.0.3.tar.xz
    rm -rf libxkbcommon-1.0.3
    run tar xf "${downloads_dir}/libxkbcommon-1.0.3.tar.xz"

    cd libxkbcommon-1.0.3
    run CFLAGS="${default_cflags}" \
        CXXFLAGS="${default_cxxflags}" \
        meson builddir/ \
        --cross-file "${meson_cross_file}" \
        --default-library=shared \
        --prefix="${sysroot}/usr" \
        --buildtype=debug \
        -Denable-x11=false \
        -Denable-xkbregistry=false \
        -Denable-wayland=false \
        -Denable-docs=false
    run ninja -C builddir
    run ninja -C builddir install
}

build_wayland_protocols() {
    download https://wayland.freedesktop.org/releases/wayland-protocols-1.20.tar.xz wayland-protocols-1.20.tar.xz
    rm -rf wayland-protocols-1.20
    run tar xf "${downloads_dir}/wayland-protocols-1.20.tar.xz"

    cd wayland-protocols-1.20
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    run PATH="${toolchain_prefix}/bin:${PATH}" \
        ./configure \
        --prefix="${sysroot}/usr" \
        --host="${target}"
    run make install
}

# libexpat.so.1.6.7
build_expat() {
    download https://github.com/libexpat/libexpat/releases/download/R_2_2_5/expat-2.2.5.tar.bz2 expat-2.2.5.tar.bz2
    rm -rf expat-2.2.5
    run tar xf "${downloads_dir}/expat-2.2.5.tar.bz2"

    cd expat-2.2.5
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    run ./configure \
        --prefix="${sysroot}/usr" \
        --host="${target}" \
        --enable-shared \
        --disable-static
    run make ${make_parallelism}
    run make install
}

# libwayland-client.so.0.3.0, libwayland-server.so.0.1.0, libwayland-cursor.so.0.0.0
build_wayland() {
    download https://wayland.freedesktop.org/releases/wayland-1.18.0.tar.xz wayland-1.18.0.tar.xz
    rm -rf wayland-1.18.0
    run tar xf "${downloads_dir}/wayland-1.18.0.tar.xz"

    cd wayland-1.18.0
    run CFLAGS="${default_cflags}" \
        CXXFLAGS="${default_cxxflags}" \
        meson builddir/ \
        --cross-file "${meson_cross_file}" \
        --default-library=shared \
        --prefix="${sysroot}/usr" \
        --buildtype=debug \
        -Dpkg_config_path="${sysroot}/usr/lib/pkgconfig" \
        -Dbuild.pkg_config_path="${toolchain_prefix}/lib/x86_64-linux-gnu/pkgconfig" \
        -Ddocumentation=false \
        -Ddtd_validation=false
    run ninja -C builddir
    run ninja -C builddir install
}

# libz.so.1.2.11
build_zlib() {
    download https://www.zlib.net/zlib-1.2.11.tar.gz zlib-1.2.11.tar.gz
    rm -rf zlib-1.2.11
    run tar xf "${downloads_dir}/zlib-1.2.11.tar.gz"

    cd zlib-1.2.11
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    run ./configure \
        --prefix="${sysroot}/usr" \
        --shared
    run make ${make_parallelism}
    run make install
}

# libgbm.so.1, libEGL.so.1, libGLESv2.so.2,
# libGLESv1_CM.so.1, libglapi.so.0.0.0
build_mesa3d() {
    download https://archive.mesa3d.org//mesa-20.3.4.tar.xz mesa-20.3.4.tar.xz
    rm -rf mesa-20.3.4
    run tar xf "${downloads_dir}/mesa-20.3.4.tar.xz"

    cd mesa-20.3.4
    run CFLAGS="${default_cflags}" \
        CXXFLAGS="${default_cxxflags}" \
        meson builddir/ \
        --cross-file "${meson_cross_file}" \
        --default-library=shared \
        --prefix="${sysroot}/usr" \
        --buildtype=debug \
        -Ddri-drivers= \
        -Dgallium-drivers=swrast \
        -Dpkg_config_path="${sysroot}/usr/lib/pkgconfig:${sysroot}/usr/share/pkgconfig" \
        -Dbuild.pkg_config_path="${toolchain_prefix}/lib/x86_64-linux-gnu/pkgconfig" \
        -Dplatforms=wayland \
        -Dglx=disabled
    run ninja -C builddir
    run ninja -C builddir install
}

build_libcap() {
    download https://git.kernel.org/pub/scm/libs/libcap/libcap.git/snapshot/libcap-2.49.tar.gz libcap-2.49.tar.gz
    rm -rf libcap-2.49
    run tar xf "${downloads_dir}/libcap-2.49.tar.gz"

    cd libcap-2.49
    make_options=(
        BUILD_CC=gcc
        COPTS="${default_cflags}"
        CROSS_COMPILE="${toolchain_prefix}/bin/${target}-"
        SHARED=no
        lib=lib
        prefix="${sysroot}/usr"
    )
    run make -C libcap \
        ${make_parallelism} \
        "${make_options[@]}"
    run make -C libcap install \
        "${make_options[@]}"
}

build_libmount() {
    download https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.36/util-linux-2.36.2.tar.xz util-linux-2.36.2.tar.xz
    rm -rf util-linux-2.36.2
    run tar xf "${downloads_dir}/util-linux-2.36.2.tar.xz"

    cd util-linux-2.36.2
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    ./configure \
        --disable-all-programs \
        --enable-libblkid \
        --enable-libmount \
        --host="${target}" \
        --prefix="${sysroot}/usr"
    make ${make_parallelism}
    make install
}

# libudev.so.1.6.3
build_libudev() {
    local version=220
    download https://www.freedesktop.org/software/systemd/systemd-${version}.tar.xz systemd-${version}.tar.xz
    rm -rf systemd-${version}
    run tar xf "${downloads_dir}/systemd-${version}.tar.xz"

    cd systemd-${version}
    patch -p1 <<'EOF'
--- a/configure	2021-03-16 21:11:01.687525961 -0700
+++ b/configure	2021-03-16 21:11:20.639418425 -0700
@@ -20510,6 +20510,7 @@
         have_efi_lds=no

 # Check whether --with-efi-ldsdir was given.
+if false; then
 if test "${with_efi_ldsdir+set}" = set; then :
   withval=$with_efi_ldsdir; EFI_LDS_DIR="$withval" && as_ac_File=`$as_echo "ac_cv_file_${EFI_LDS_DIR}/elf_${EFI_ARCH}_efi.lds" | $as_tr_sh`
 { $as_echo "$as_me:${as_lineno-$LINENO}: checking for ${EFI_LDS_DIR}/elf_${EFI_ARCH}_efi.lds" >&5
@@ -20558,6 +20559,7 @@

 done
 fi
+fi  # if false

         if test "x$have_efi_lds" = xyes; then :

EOF
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    run PKG_CONFIG_PATH="${sysroot}/usr/lib/pkgconfig" \
        ./configure \
        --prefix="${sysroot}/usr" \
        --host="${target}" \
        GLIB_CFLAGS=' ' \
        GLIB_LIBS=' ' \
        ac_cv_func_malloc_0_nonnull=yes \
        ac_cv_func_realloc_0_nonnull=yes
    make ${make_parallelism} \
        src/shared/errno-to-name.h \
        src/shared/errno-from-name.h \
        src/shared/af-to-name.h \
        src/shared/af-from-name.h \
        src/shared/cap-to-name.h \
        src/shared/cap-from-name.h \
        src/shared/arphrd-to-name.h \
        src/shared/arphrd-from-name.h
    make ${make_parallelism} libudev.la src/libudev/libudev.pc

    run install src/libudev/libudev.h "${sysroot}/usr/include"
    run install src/libudev/libudev.pc "${sysroot}/usr/lib/pkgconfig"
    run install .libs/libudev.so "${sysroot}/usr/lib"
    run install .libs/libudev.so.1 "${sysroot}/usr/lib"
    run install .libs/libudev.so.1.6.3 "${sysroot}/usr/lib"
}

build_retroarch() {
    download https://codeload.github.com/libretro/RetroArch/tar.gz/v1.9.5 RetroArch-1.9.5.tar.gz
    rm -rf RetroArch-1.9.5
    run tar xf "${downloads_dir}/RetroArch-1.9.5.tar.gz"

    cd RetroArch-1.9.5
    patch -p1 <"${scripts_dir}/retroarch-input.patch"
    # TODO: libhq2x.so
    # TODO: --enable-vulkan --enable-kms --enable-alsa
    extra_cppflags="-DWL_EGL_PLATFORM"
    run PATH="${toolchain_prefix}/bin:${PATH}" \
        CC="${toolchain_cc}" \
        CXX="${toolchain_cxx}" \
        CFLAGS="${default_cflags} ${extra_cppflags}" \
        CXXFLAGS="${default_cxxflags} ${extra_cppflags}" \
        LDFLAGS="-Wl,--as-needed -lffi -lwayland-server -lglapi -lexpat -Wl,--no-as-needed" \
        PKG_CONFIG_PATH="${sysroot}/usr/lib/pkgconfig" \
        ./configure \
        --prefix="${sysroot}/usr" \
        --host="${target}" \
        --enable-opengl \
        --enable-opengles \
        --enable-udev \
        --enable-egl \
        --disable-builtinzlib \
        --disable-opengl1 \
        --enable-zlib
    run make ${make_parallelism}
    run "${toolchain_prefix}/bin/${target}-strip" \
        -o "${sysroot}/usr/bin/retroarch" \
        ./retroarch
}

build_strace() {
    download https://strace.io/files/5.16/strace-5.16.tar.xz strace-5.16.tar.xz
    rm -rf strace-5.16
    run tar xf "${downloads_dir}/strace-5.16.tar.xz"

    cd strace-5.16
    export CC="${toolchain_cc}" CXX="${toolchain_cxx}" CFLAGS="${default_cflags}" CXXFLAGS="${default_cxxflags}"
    run ./configure \
        --prefix="${sysroot}/usr" \
        --host="${target}"
    run make ${make_parallelism}
    run make install
}

build_gdbserver() {
    download ftp://ftp.gnu.org/gnu/gdb/gdb-8.3.1.tar.xz gdb-8.3.1.tar.xz
    rm -rf gdb-8.3.1
    run tar xf "${downloads_dir}/gdb-8.3.1.tar.xz"
    rm -rf gdb-build
    mkdir -p gdb-build

    cd gdb-build
    run CC="${toolchain_cc}" \
        CXX="${toolchain_cxx}" \
        AR="${toolchain_ar}" \
        CFLAGS="${default_cflags}" \
        CXXFLAGS="${default_cxxflags}" \
        ../gdb-8.3.1/configure \
        --prefix="${sysroot}/usr" \
        --host="${target}" \
        --enable-gdbserver=yes
    run make ${make_parallelism}
    run make -C gdb/gdbserver install
}

build_host_gdb() {
    download ftp://ftp.gnu.org/gnu/gdb/gdb-8.3.1.tar.xz gdb-8.3.1.tar.xz
    rm -rf gdb-8.3.1
    tar xf "${downloads_dir}/gdb-8.3.1.tar.xz"
    rm -rf gdb-host-build
    mkdir -p gdb-host-build

    cd gdb-host-build
    run ../gdb-8.3.1/configure \
        --prefix="${toolchain_prefix}" \
        --with-expat \
        --enable-targets=all \
        --enable-gdbserver=no \
        --enable-tui
    run make ${make_parallelism}
    run make install
}

download() {
    local url="${1}"
    local file="${downloads_dir}/${2}"
    mkdir -p "${downloads_dir}"
    if ! [[ -f "${file}" && -s "${file}" ]]; then
        run wget "${url}" -O "${file}"
    fi
}

run() {
    local command=("${@}")

    local blue=$'\e[0;34m'
    local green=$'\e[0;32m'
    local red=$'\e[0;31m'
    local reset=$'\e[0m'

    printf '%s$ %scd %q && ' "${blue}" "${green}" "${PWD}"
    pretty_print_command "${command[@]}"
    printf '%s\n' "${reset}"

    env "${command[@]}" || {
        local code="${?}"
        printf '%serror: command failed: cd %q && ' "${red}" "${PWD}"
        pretty_print_command "${command[@]}"
        printf '%s\n' "${reset}"
        return "${code}"
    }
}

pretty_print_command() {
    local command=("${@}")
    printf '%q' "${command[0]}"
    if [ "${#command[@]}" -gt 1 ]; then
        printf ' %q' "${command[@]:1}"
    fi
}

main "${@}"

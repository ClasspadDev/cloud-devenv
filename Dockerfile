FROM debian:bullseye-slim as base

# ENV PREFIX "/opt/cross"

ENV PATH /opt/cross/bin:$PATH
ENV SDK_DIR /opt/cross/hollyhock-3/sdk

# TODO: maybe put the build stuff into a separate "prereq" image and publish a "clean" version without GCC source and stuff,
# but it could be helpful is some wanted to add some lib into it so dunno ...

RUN apt-get -qq update
RUN apt-get -y install curl git cmake

# ===================================================================================================================================================
# STAGE 1 : Build dependencies
# ===================================================================================================================================================
FROM debian:bullseye-slim AS prereqs

ENV PREFIX="/usr/local"
ENV TARGET="sh4-elf"

RUN apt-get -qq update
RUN apt-get -y install build-essential libmpfr-dev libmpc-dev libgmp-dev libpng-dev ppl-dev curl git cmake texinfo

# Build Binutils
RUN mkdir /opt/cross/
WORKDIR /opt/cross/

RUN curl -L http://ftpmirror.gnu.org/binutils/binutils-2.34.tar.bz2 | tar xj
RUN mkdir binutils-build
WORKDIR /opt/cross/binutils-build
RUN ../binutils-2.34/configure --target=${TARGET} --prefix=${PREFIX} --disable-nls \
        --disable-shared --disable-multilib
RUN make -j$(nproc)
RUN make install

# cleaning up
RUN rm -rf /opt/cross/binutils-2.34
# RUN rm -rf /opt/cross/binutils-build

# FROM binutils AS gcc
WORKDIR /opt/cross/
RUN curl -L http://ftpmirror.gnu.org/gcc/gcc-10.1.0/gcc-10.1.0.tar.xz | tar xJ
RUN mkdir /opt/cross/gcc-build
WORKDIR /opt/cross/gcc-build
# --prefix=$prefix
RUN ../gcc-10.1.0/configure --target=${TARGET} --prefix=${PREFIX} \ 
        --enable-languages=c,c++ \
		--with-newlib --without-headers --disable-hosted-libstdcxx \
        --disable-tls --disable-nls --disable-threads --disable-shared \
        --enable-libssp --disable-libvtv --disable-libada \
        --with-endian=big --enable-lto --with-multilib-list=m4-nofpu
RUN make -j$(nproc) inhibit_libc=true all-gcc
RUN make install-gcc

RUN make -j$(nproc) inhibit_libc=true all-target-libgcc
RUN make install-target-libgcc

# cleaning up
RUN rm -rf /opt/cross/gcc-10.1.0
# RUN rm -rf /opt/cross/gcc-build


# ========================================================================
# Build and Install Newlib from diddyholz/newlib-cp2
# ========================================================================

WORKDIR /opt/cross/
RUN git clone https://github.com/diddyholz/newlib-cp2 newlib
WORKDIR /opt/cross/newlib

# Setup environment variables for Newlib
ENV PREFIX="$SDK_DIR/newlib"
ENV TARGET="sh4-elf"

RUN mkdir build
WORKDIR /opt/cross/newlib/build
RUN ../configure --target=$TARGET --prefix=$PREFIX
RUN make -j$(nproc)
RUN make install




# ===================================================================================================================================================
# STAGE 2 : User Setup and SDK Installation
# ===================================================================================================================================================
FROM debian:bullseye-slim

ENV USERNAME="dev"
ENV SDK_DIR=/opt/cross/hollyhock-3/sdk


# Copy installed toolchain and librarie
COPY --from=prereqs /usr/local /usr/local
COPY --from=prereqs /opt/cross/newlib /opt/cross/newlib
# COPY --from=newlib /usr/local /usr/local
RUN apt-get -qq update && apt-get -qqy install make libmpc3 sudo git && apt-get -qqy clean

# Clone and build Hollyhock SDK
WORKDIR /opt/cross/
RUN git clone https://github.com/ClasspadDev/hollyhock-3.git
WORKDIR /opt/cross/hollyhock-3/sdk
RUN make -j$(nproc)

USER root

# Fixing some files
RUN mkdir -p /opt/cross/hollyhock-3/sdk/newlib/
RUN ln -s /usr/local/sh-elf/ /opt/cross/hollyhock-3/sdk/newlib/sh-elf
# Adding a sh4eb-nofpu-elf variant to sh4-elf
WORKDIR /usr/local/bin
RUN for f in sh4-elf-* ; do ln -s "$f" "sh4eb-nofpu-elf-"$(echo "$f" | cut -d'-' -f3-) ; done

COPY setup.sh /tmp

# Create and configure user
RUN useradd -rm -d /home/$USERNAME -s /bin/bash -g root -G sudo -u 1001 -p "$(openssl passwd -1 ${USERNAME})" $USERNAME
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# RUN echo ${USERNAME}:${USERNAME} | chpasswd
USER $USERNAME
WORKDIR /home/$USERNAME
RUN echo "export SDK_DIR=${SDK_DIR}" >> ~/.bashrc

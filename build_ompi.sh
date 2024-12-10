#!/bin/bash


DEPS_DIR=/tmp

cd $DEPS_DIR
export CC=gcc
export CXX=g++
export FC=gfortran


git clone https://github.com/openucx/ucx.git
cd ucx
git checkout v1.13.1
./autogen.sh
mkdir -p build && cd build
if [[ ! -z "$1" ]] && [[ $1 == "--cuda" ]]; then
	../contrib/configure-opt --prefix=/opt/ucx \
	    --without-rocm \
        --with-cuda=/usr/local/cuda \
	    --without-knem --without-xpmem \
        --enable-optimizations \
        --disable-logging --disable-debug --enable-assertions --enable-params-check \
        --disable-examples
else
    ../contrib/configure-opt --prefix=/opt/ucx \
        --with-rocm=/opt/rocm --without-knem \
        --without-xpmem  --without-cuda \
        --enable-optimizations  \
        --disable-logging --disable-debug --enable-assertions --enable-params-check \
        --disable-examples
fi
make -j $(nproc)
make install



#
#
# OpenMPI
#
#

# Get latest-and-greatest OpenMPI version:
# Configure with UCX
# NOTE: With OpenMPI 4.0 and above, there could be compilation errors from “btl_uct” component.
# This component is not critical for using UCX; so it could be disabled this way:  --enable-mca-no-build=btl-uct

cd $DEPS_DIR
git clone --recursive -b v5.0.0rc9 https://github.com/open-mpi/ompi.git
cd ompi
./autogen.pl
mkdir -p build && cd build
if [[ ! -z "$1" ]] && [[ $1 == "--cuda" ]]; then
	../configure --prefix=/opt/ompi --with-ucx=/opt/ucx \
        --with-cuda=/usr/local/cuda \
        --enable-mca-no-build=btl-uct  \
        --enable-mpi-f90 --enable-mpi-c \
        --with-pmix CC=$(which gcc)  \
        --enable-mpi \
        --disable-man-pages \
        --enable-mpi-fortran=yes \
        --disable-debug
else
    ../configure --prefix=/opt/ompi --with-ucx=/opt/ucx \
        --enable-mca-no-build=btl-uct  \
        --enable-mpi-f90 --enable-mpi-c \
        --with-pmix CC=$(which gcc)  \
        --enable-mpi \
        --disable-man-pages \
        --enable-mpi-fortran=yes \
        --disable-debug
fi
make -j $(nproc)
make install

#
# End of file
# Author: Suyash Tandon
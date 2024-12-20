#!/bin/bash

VERSION="hdf5-1.14.0"
VERS=${VERSION%.[0-9]*}
TARBALL="${VERSION}.tar.gz"

OMPI_VERSION=intel-oneapi
ROCM_VERSION=5.6.0

TRGT_DIR=/share/contrib-modules

# TODO: use cmake to specify installation directory
INSTALLDIR="${TRGT_DIR}/hdf5/${VERSION}-ompi-${OMPI_VERSION}-rocm${ROCM_VERSION}"
mkdir -p ${INSTALLDIR}

cd ${TRGT_DIR}/hdf5

echo "Downloading HDF5 code..."
rm -f ${TARBALL}
wget https://support.hdfgroup.org/ftp/HDF5/releases/${VERS}/${VERSION}/src/${TARBALL}
echo "done."

printf "Wiping ${VERSION}_source..."
rm -rf ${VERSION}_source
echo "done."

echo "Unpacking to ${VERSION}_source..."
tar -zxvf ${TARBALL}
mv ${VERSION} ${VERSION}_source
echo "done."

cd ${VERSION}_source/

echo "Configure..."
CC=mpiicc CXX=mpiicx FC=mpiifort ./configure --enable-parallel --enable-fortran --disable-shared --prefix="$INSTALLDIR"

make -j 48
make -j 48 check 

echo "Installing to $INSTALLDIR..."
make install
echo "... finished."
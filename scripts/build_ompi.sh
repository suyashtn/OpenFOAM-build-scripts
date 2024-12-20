#!/bin/bash

DEPS_DIR=/tmp
TRGT_DIR=/share/contrib-modules

cd $DEPS_DIR
export CC=clang
export CXX=clang++
export FC=flang-new
#export CXXFLAGS="-Wno-unused-but-set-variable"
#export CFLAGS="-Wno-unused-but-set-variable"

ucx_ver=1.16.0
#ompi_ver=5.0.0rc2
ompi_ver=5.0.3
cuda_ver=12.0
#
# Extract ROCm version
#
ROCM_PATH="$ROCM_PATH"
path_string="/opt/rocm-"
rocm_ver=${ROCM_PATH#$path_string}
rocm_ver=$(echo "$rocm_ver" | sed 's:/*$::')
# echo "ROCM VERSION: $rocm_ver"

git clone https://github.com/openucx/ucx.git
cd ucx
git checkout v${ucx_ver}
./autogen.sh
mkdir -p build && cd build
if [[ ! -z "$1" ]] && [[ $1 == "--cuda" ]]; then
	../contrib/configure-opt \
	    --prefix="${TRGT_DIR}/ucx/ucx${ucx_ver}-cuda${cuda_ver}" \
	    --without-rocm \
	    --without-knem \
		--with-gdrcopy=/usr \
	    --with-cuda=/share/modules/CUDA/12.0
else
	../contrib/configure-opt \
    	    --prefix="${TRGT_DIR}/ucx/ucx${ucx_ver}-rocm${rocm_ver}" \
    	    --with-rocm=${ROCM_PATH} \
    	    --without-knem \
    	    --without-cuda    
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
git clone --recursive -b v${ompi_ver} https://github.com/open-mpi/ompi.git
cd ompi
./autogen.pl
mkdir -p build && cd build
if [[ ! -z "$1" ]] && [[ $1 == "--cuda" ]]; then
	../configure --prefix="${TRGT_DIR}/openmpi/ompi${ompi_ver}-ucx${ucx_ver}-cuda${cuda_ver}" --with-ucx=${TRGT_DIR}/ucx/ucx${ucx_ver}-cuda${cuda_ver} --without-verbs --enable-mca-no-build=btl-uct --with-cuda=/share/modules/CUDA/12.0
else
	../configure --prefix="${TRGT_DIR}/openmpi/ompi${ompi_ver}-ucx${ucx_ver}-rocm${rocm_ver}" --with-ucx=${TRGT_DIR}/ucx/ucx${ucx_ver}-rocm${rocm_ver} --without-verbs --enable-mca-no-build=btl-uct
fi
make -j $(nproc)
make install

#EOF
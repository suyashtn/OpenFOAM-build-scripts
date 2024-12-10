#! /usr/bin/env bash
#
CDIR=`pwd`
SDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"

# git clone command
GIT_CLONE_CMD="git clone --progress --verbose"

function clean()
{
    if [[ -n "${OPENFOAM_VERSION}" ]]; then
        rm -fr ${PREFIX}/ThirdParty-${OPENFOAM_VERSION}/petsc*
        rm -fr ${PREFIX}/ThirdParty-${OPENFOAM_VERSION}/scotch*
        rm -fr ${PREFIX}/OpenFOAM-${OPENFOAM_VERSION}/build
    fi
}



function build_interactive()
{
    # select the desired version of OpenFOAM
    echo "
    #------------------------------------------------------------------------------
    # =========		   |
    # \\      /  F ield       | OpenFOAM: The Open Source CFD Toolbox
    #  \\    /   O peration   |
    #   \\  /    A nd         |www.openfoam.com
    #    \\/     M anipulation|
    #------------------------------------------------------------------------------

    Select the desired version of openFOAM (e.g.: 2012, 2006, etc.)
    Default version: 2206

     *Note: PETSc has not been tested on versions earlier than 1912"
    read -p "Enter the version: " v

    if [ -z $v ]
    then
	echo "using the default version (v2206)"
	version=v2206
    else
	echo "selected version v${v}"
	version=v${v}
    fi


    OPENFOAM_VERSION=version

    build $version
}


function build()
{
    version=$1
    branch="suyash/hmm"

    # 1. check if the source dirs already exist
    if [ -d ${PREFIX}/OpenFOAM-${version} ] && [ -d ${PREFIX}/ThirdParty-${version} ]
    then
	echo "
Source directories exist! Move on to building from source.
=================================="
    else
	# clone the selected version
        cd ${PREFIX}
	${GIT_CLONE_CMD} -b ${branch} git@github.com:ROCm/OpenFOAM_HMM.git OpenFOAM-${version}
	${GIT_CLONE_CMD} -b ${version} https://develop.openfoam.com/Development/ThirdParty-common.git ThirdParty-${version}
        cd -
    fi

    # 2. setup the environment
    cp -rvu ${CDIR}/scripts ${PREFIX}/OpenFOAM-${version}/.

    # 2.1 Copy from nvidia-files, if building for CUDA platforms
    if [[ $CUDA -eq 1 ]]
    then
        # 1. copy the setup.sh
        cp ${CDIR}/nvidia-files/setup.sh ${PREFIX}/OpenFOAM-${version}/scripts/.
        # 2. copy wmake/rules 
        cp ${CDIR}/nvidia-files/c*Opt ${PREFIX}/OpenFOAM-${version}/wmake/rules/linux64Clang/.
        cp ${CDIR}/nvidia-files/openmp* ${PREFIX}/OpenFOAM-${version}/wmake/rules/General/Clang/.
        cp ${CDIR}/nvidia-files/link-c++ ${PREFIX}/OpenFOAM-${version}/wmake/rules/General/Clang/.
        # 3. copy src/OpenFOAM/fields
        cp ${CDIR}/nvidia-files/FieldFunctions*.C ${PREFIX}/OpenFOAM-${version}/src/OpenFOAM/fields/Fields/Field/.
        cp ${CDIR}/nvidia-files/GeometricFieldFunctionsM.C ${PREFIX}/OpenFOAM-${version}/src/OpenFOAM/fields/GeometricFields/GeometricField/.    
    fi 

    echo "
source OpenFOAM-${version}/scripts/setup.sh
=================================="
    cd ${PREFIX}/OpenFOAM-${version}
    source scripts/setup.sh
    cd -

    #identify the GPU arch - gfx90a, gfx942, etc.
    export GPU_ARCH=`${ROCM_PATH}/bin/rocm_agent_enumerator | tail -n 1`
    echo "================================== "
    echo "Building for GPU Arch: $GPU_ARCH"
    echo "=================================="

    #3. Build UMPIRE interface
    if [ ! -d ${PREFIX}/ADD_UMPIRE ]
    then 
        cp -r ${CDIR}/ADD_UMPIRE ${PREFIX}/.
    fi
    cd ${PREFIX}/ADD_UMPIRE
    source_file=provide_umpire_pool.cpp
    if [ ! -f ${source_file} ]
    then
        echo "ERROR: ${source_file} not found. This will cause build errors!! Please check the setup."
        exit 1
    fi 
    if [[ $CUDA -eq 1 ]]
    then
        # compile and object with nvcc, and use a linker for dynamic parallelism:
        # https://stackoverflow.com/questions/22115197/dynamic-parallelism-undefined-reference-to-cudaregisterlinkedbinary-linking
        # cp ${source_file} provide_umpire_pool_cuda.cpp
        nvcc -arch=all-major -x cu -c -O2 -I${UMPIRE4FOAM}/include provide_umpire_pool_cuda.cpp
        nvcc -arch=all-major -dlink -o provide_umpire_pool.o provide_umpire_pool_cuda.o -L${UMPIRE4FOAM}/lib -lumpire -L${CUDA4FOAM}/lib64 -lcudart -lcudadevrt -lcuda
    else
        clang++ -c -O2 -I${UMPIRE4FOAM}/include ${source_file}
    fi

    # 4. set up third-party libraries
    cd ${PREFIX}/ThirdParty-${version}

    # 4.1 need to download SCOTCH
    s_v=6.1.3
    echo "selecting scotch version ${s_v}"
    if [ -d scotch_${s_v} ]
    then
	echo "
scotch_${s_v} already exists!
=================================="
    else
	${GIT_CLONE_CMD} -b v${s_v} https://gitlab.inria.fr/scotch/scotch.git scotch_${s_v}
    fi
    sed -i -e "s|.*SCOTCH_VERSION=scotch_.*|SCOTCH_VERSION=scotch_${s_v}|g" ${PREFIX}/OpenFOAM-${version}/etc/config.sh/scotch
    ./Allwmake -j -l

    # 5. check system readiness before building
    echo "
Check system readiness before building OpenFOAM.
use: foamSystemCheck
================================="

    if [[ -z "${USER+x}" ]]; then
	export USER=$(whoami)
    fi

    if $SHELL foamSystemCheck | grep -iq 'fail'; then
        echo "foamSystemCheck failed" 1>&2
        exit 1
    fi

    # 6. Build openFOAM
    echo "
Building OpenFOAM.
================================="
    cd ${PREFIX}/OpenFOAM-${version}
    ./Allwmake -j -l

    echo "
========================================
Done OpenFOAM Allwmake
========================================"

    # 7. Test OpenFOAM installation
    echo "
Check OpenFOAM installation
use: foamInstallationTest
================================="
    cd ${PREFIX}
    $SHELL foamInstallationTest
}

function load_benchmark()
{
    HPC_motorbike_dir="HPC_Benchmark/incompressible/simpleFoam/HPC_motorbike/Large/v1912"
    cd $PREFIX
    ${GIT_CLONE_CMD} https://develop.openfoam.com/committees/hpc.git HPC_Benchmark 
    echo "
## Configuring HPC_motorbike case...
"
    # configure and setup HPC_motorbike
    # 1. Reduce the time to run 20 steps only
    sed -i -e "s|endTime         500;|endTime         20;|g" ${PREFIX}/${HPC_motorbike_dir}/system/controlDict
    # 2. modify and update mirrorMeshDict to avoid errors with mesh generation with newer OpenFOAM version
    sed -i -e "s|vector|normal  |g" ${PREFIX}/${HPC_motorbike_dir}/system/mirrorMeshDict
    # 3. increase the decomposition levels to create the mesh potentially faster
    # 16, 32, 64 and 96 cores - 30, 20, 15 and 15mins, resp. But mesh grows +1.5% between 16-96 core.
    Cores=$(( $(lscpu | awk '/^Socket\(s\)/{ print $2 }') * $(lscpu | awk '/^Core\(s\) per socket/{ print $4 }') ))
    sed -i -e "s|.*numberOfSubdomains.*|numberOfSubdomains ${Cores};|g" ${PREFIX}/${HPC_motorbike_dir}/system/decomposeParDict
    # 4. change the preconditioner to diagonal
    sed -i -e "s|preconditioner.*|preconditioner  diagonal;|g" ${PREFIX}/${HPC_motorbike_dir}/system/fvSolution


    echo "
     ---------------------------------------------------------------------
     The HPC_motorbike case Large with ~64 Million cells, is configured in:
     ${PREFIX}/${HPC_motorbike_dir} .
     ---------------------------------------------------------------------

    Please source the openfoam environment, e.g.: source <your-path-to>/OpenFOAM-version/etc/bashrc.

    Convenient run script is included, with usage: 
    =================================
    usage: ./bench-hpc-motorbike.sh [options]
    options:
        -h | --help      Prints the usage
        -c | --clean     Clean the case directory
        -d | --device-name user-defined name to add to logs (default: mi300a)
        -g | --ngpus     #GPUs to be used (between 1-4), defaults to 1
        -j | --threads   #OpenMP threads (default: 1)
        -n | --mpi-ranks #MPI ranks to be used. (default ranks=gpus)
        -t | --time-steps #time-steps to run for (default: 20) 
        -r | --run-only  skip mesh build, and directly run the case
"
}


function usage()
{
    echo "

This is a build script designed to configure and install OpenFOAM with OpenMP offloading using HMM.
=================================
usage: $0

       -h | --help          Prints the usage
       [--prefix]           Base installation directory, defaults to CWD
       [--openfoam-version] OpenFOAM version (e.g.: 2112, 2206, etc.)
       [--cuda]             Build for NVIDIA platforms with CUDA
       [--load-benchmark]   Load OpenFOAM HPC Benchmarks
       [--load-benchmark-only]  Skip build and load the benchmakrs only

"
}


parse_args(){
    set +u
    while (( "$#" )); do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --prefix)
                PREFIX="$(realpath $2)"
                shift 2
                ;;
            --openfoam-version)
                OPENFOAM_VERSION="v$2"
                shift 2
                ;;
            --clean)
                POST_CLEAN="true"
                shift 1
                ;;
            --cuda)
                CUDA=1
                shift 1
                ;;
            --load-benchmark)
                LOAD_BENCHMARKS=1
                shift 1
                ;;
            --load-benchmark-only)
                LOAD_BENCHMARKS_ONLY=1
                shift 1
                ;;
            -*|--*=|*) # unsupported flags
                echo "Error: Unsupported flag $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${OPENFOAM_VERSION+x}" ]]; then
        INTERACTIVE_BUILD="true"
    fi

    if [[ -z "${LOAD_BENCHMARKS+x}" ]]; then
        LOAD_BENCHMARKS=0
    fi

    if [[ -z "${LOAD_BENCHMARKS_ONLY+x}" ]]; then
        LOAD_BENCHMARKS_ONLY=0
    fi

    if [[ -z "${CUDA+x}" ]]; then
        CUDA=0
    fi

    if [[ -z "${PREFIX+x}" ]]; then
        PREFIX="$CDIR"
    else
        mkdir -p ${PREFIX}
    fi
}


#*******************************************************
#
# This is the Main part of this bash script which calls
# the functions above based on user choices
#
#*******************************************************


parse_args $*

if [[ $LOAD_BENCHMARKS_ONLY -eq 1 ]]; then
    load_benchmark    
else
    if [[ -z "${OPENFOAM_VERSION+x}" ]]; then
        build_interactive
    else
        build $OPENFOAM_VERSION
    fi

    if [[ -n "${POST_CLEAN+x}" ]]; then
        clean
    fi

    if [[ $LOAD_BENCHMARKS -eq 1 ]]; then
        load_benchmark    
    fi
fi

#
# End of file
# Author: Suyash Tandon

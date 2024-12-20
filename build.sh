#! /usr/bin/env bash
#
CDIR=`pwd`
SDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"



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

    # check if the source dirs already exist
    if [ -d ${PREFIX}/OpenFOAM-${version} ] && [ -d ${PREFIX}/ThirdParty-${version} ]
    then
	echo"
Source directories exist! Move on to building from source.
=================================="
    else
	# clone the selected version
        cd ${PREFIX}
	git clone -b OpenFOAM-${version} https://develop.openfoam.com/Development/openfoam.git OpenFOAM-${version}
	git clone -b ${version} https://develop.openfoam.com/Development/ThirdParty-common.git ThirdParty-${version}
        cd -
    fi

    # setup the environment
    echo "
source OpenFOAM-${version}/etc/bashrc
=================================="
    source ${PREFIX}/OpenFOAM-${version}/etc/bashrc

    # set up third-party libraries
    cd ${PREFIX}/ThirdParty-${version}

    # need to download SCOTCH
    s_v=7.0.6
    echo "selecting scotch version ${s_v}"
    if [ -d scotch_${s_v} ]
    then
	echo "
scotch_${s_v} already exists!
=================================="
    else
	git clone -b v${s_v} https://gitlab.inria.fr/scotch/scotch.git scotch_${s_v}
    fi
    sed -i -e "s|.*SCOTCH_VERSION=scotch_.*|SCOTCH_VERSION=scotch_${s_v}|g" ${PREFIX}/OpenFOAM-${version}/etc/config.sh/scotch
    ./Allwmake -j -q

    # need to download PETSc
    p_v=3.22.2
    echo " selecting petsc version ${p_v} with HIP"
    if [ -d petsc-${p_v} ]
    then
	echo "
petsc-${p_v} already exists!
=================================="
    else
        if [[ ${p_v} == "3.18.1" ]] || [[ ${p_v} == "3.18.2" ]]; then
            # PETSc 3.18.1 and 3.18.2 have issues with GAMG and CUPM interface, but fixes already included in `main`
            # for 3.18.1 commit="2f91b18a518e38a1bb5cc181d7f42327698cc9f1"
            # for 3.18.2
            commit="e874ec00d637a86419bb2cc912cf88b33e5547ef"
            git clone https://gitlab.com/petsc/petsc.git petsc-${p_v}
            cd petsc-${p_v}
            git checkout ${commit}
            cd ..
        else
            git clone -b v${p_v} https://gitlab.com/petsc/petsc.git petsc-${p_v}
        fi
	fi
    sed -i -e "s|petsc_version=petsc-.*|petsc_version=petsc-${p_v}|g" ${PREFIX}/OpenFOAM-${version}/etc/config.sh/petsc
    if [[ -v CUDA ]] && [[ $CUDA -eq 1 ]]; then
	    PETSC_MAKE=makePETSC.cuda
    else
	    PETSC_MAKE=makePETSC.hip
    fi
    cp ${SDIR}/${PETSC_MAKE} ${PREFIX}/ThirdParty-${version}/.
    cd ${PREFIX}/ThirdParty-${version}

    if ! ./${PETSC_MAKE} -no-hypre; then
	echo "
Check your configuration settings again and retry building PETSc lib.
================================="
        exit 1
    fi

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

    echo "
Building OpenFOAM.
This is a regular build. The petsc4Foam inteface lib will be built separately.
================================="
    cd ${PREFIX}/OpenFOAM-${version}
    ./Allwmake -j -q -l

    echo "
========================================
Done OpenFOAM Allwmake
========================================"

    echo "
Building PETSc4FOAM library in modules/external-solver.
This creates an interface between OpenFOAM and PETSc solver.
================================="

    git submodule update --init ${PREFIX}/OpenFOAM-${version}/modules/external-solver
    cd ${PREFIX}/OpenFOAM-${version}/modules/external-solver
    ./Allwmake -j -q -l
    echo "
========================================
Done PETSc4FOAM (modules/external-solver) Allwmake
========================================"

    echo "
Check OpenFOAM installation
use: foamInstallationTest
================================="
    cd ${PREFIX}
    echo "
Before running lets verify if PETSc lib can be found
================================="
    eval $(foamEtcFile -sh -config petsc -- -force)
    if ! foamHasLibrary -verbose petscFoam; then
        echo "
Looks like PETSc was not loaded properly. Check your installation again.
================================="
        exit 1
    fi

    $SHELL foamInstallationTest
}


function usage()
{
    echo "

This is a build script designed to configure and install OpenFOAM and PETSc.
=================================
usage: ./build.sh

       -h | --help	Prints the usage
       [--prefix] Base installation directory, defaults to CWD
       [--openfoam-version] OpenFOAM version (e.g.: 2012, 2006, etc.)

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

if [[ -z "${OPENFOAM_VERSION+x}" ]]; then
    build_interactive
else
    build $OPENFOAM_VERSION
fi

if [[ -n "${POST_CLEAN+x}" ]]; then
    clean
fi


#
# End of file
# Author: Suyash Tandon
# Contact: suyash.tandon@amd.com

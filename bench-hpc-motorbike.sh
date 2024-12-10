#!/bin/bash
#
# Script is expected to be in, and executed from, the root directory
# of the HPC_Benchmark directory
cd ${0%/*} || exit 1    # Run from this directory
CDIR=`pwd`

# time now
now=$(date +'%m%d%Y-%H%M')

# set the benchmark case
benchmark_case=incompressible/simpleFoam/HPC_motorbike/Large/v1912

function setup()
{
    # setting the env
    export OMP_NUM_THREADS=${OMP_THREADS}
    MAX_CORES=$(( $(lscpu | awk '/^Socket\(s\)/{ print $2 }') * $(lscpu | awk '/^Core\(s\) per socket/{ print $4 }') ))
    if [[ ${MPI_RANKS} -le 0 ]] ||  [[ ${MPI_RANKS} -gt ${MAX_CORES} ]]; then  
        # ERR condition
        echo " ERROR: This system only has $MAX_CORES physical cores."
        echo "        Please change your current selection of MPI ranks: ${MPI_RANKS} to run the script!  "
        exit 1
    fi

    case "${DEVICE}" in
        hip|HIP|Hip)
            platform=ROCR
            ;;
        cuda|CUDA|Cuda)
            platform=CUDA
            ;;
        *|--*=|*) # unsupported offloading
            echo " ERROR: Unsupported offloading type - ${DEVICE}" 
            echo "        Available Options: HIP or CUDA. Check your runtime options!"
            exit 1
            ;;
    esac
    
    # Grab the max available devices 
    if [ ${platform} = CUDA ]
    then 
        MAX_DEVICES=$(nvidia-smi -L | wc -l)
    else
        MAX_DEVICES=$(rocminfo | grep "amdgcn-amd-amdhsa--" | wc -l)
    fi

    if [[ ${NGPUS} -le 0 ]] ||  [[ ${NGPUS} -gt ${MAX_DEVICES} ]]; then  
        # ERR condition
        echo " ERROR: This script is designed to run with a maximum of ${MAX_DEVICES} APUs/GPUs."
        echo "        Either change your current selection of APUs: ${NGPUS} or modify the 'MAX_DEVICES' count in the script!  "
        exit 1
    fi

    # gpu_string="0"
    # for (( gpunum=1; gpunum<${NGPUS} ; gpunum++ )) ; do
    #     gpu_string+=",${gpunum}"
    # done
    # export HIP_VISIBLE_DEVICES=${gpu_string}

    # calculate the last and prev time step based on input
    END_TIME=$TIME_STEPS
    PREV_TIME=$(( $END_TIME - 1 ))   

    # set the time steps in system/controlDict
    sed -i -e "s|endTime    .*|endTime         ${TIME_STEPS};|g" ${CDIR}/HPC_Benchmark/${benchmark_case}/system/controlDict
    
    # Source tutorial run functions
    . $WM_PROJECT_DIR/bin/tools/RunFunctions

    cd $WM_PROJECT_DIR
    git_hash=`git show -s --format="%h"`
    git_branch=`git branch --show-current`
    echo "================================================================================"
    echo " Running HPC_motorbike (Large) benchmark"
    echo "  "
    echo " MPI Ranks       : ${MPI_RANKS}"
    echo " OMP_NUM_THREADS : ${OMP_THREADS}"
    echo " APUs/GPUs       : ${NGPUS}"
    echo " Platform        : ${DEVICE}" 
    echo " Git commit      : ${git_hash} -- ${git_branch}"
    echo "================================================================================"

    # Setup the HPC-motorbike benchmark (Large) case using the folloring commands:
    cd ${CDIR}/HPC_Benchmark/${benchmark_case}
    if [ ! -x Allrun ] && [ ! -x Allclean ] && [ ! -x AllmeshS ]
    then
        chmod +x All*
    fi
    app=`getApplication`
    cp -r 0.org 0
    # Clean logs/
    rm -rf ${CDIR}/HPC_Benchmark/${benchmark_case}/logs/*
}

function generateMesh()
{
    # using max CPU cores avaiable on the system to generate the Mesh
    # 16, 32, 64 and 96 cores - 30, 20, 15 and 15mins, resp. But mesh grows +1.5% between 16-96 core.
    # We use MAX_CORES on the system - evaluated in setup()
    if [ ${platform} = ROCR ]
    then
      sed -i -e "s|.*numberOfSubdomains.*|numberOfSubdomains ${MAX_CORES};|g" ${CDIR}/HPC_Benchmark/${benchmark_case}/system/decomposeParDict
      export ${platform}_VISIBLE_DEVICES=" "     
    else
        sed -i -e "s|.*numberOfSubdomains.*|numberOfSubdomains 16;|g" ${CDIR}/HPC_Benchmark/${benchmark_case}/system/decomposeParDict
    fi
    # setting devices to not visible to force Mesh generation to run on host CPUs, which is faster/stable than offloading to APUs for now
    ./AllmeshL
    if [ ${platform} = ROCR ]
    then
        unset ${platform}_VISIBLE_DEVICES
    fi
    # store mesh log files for reference
    mkdir -p meshStats
    mv log.blockMesh log.snappy* log.decomposePar log.reconst* log.mirrorMesh* meshStats/.
}

function checkMesh()
{
    # 1. AllmeshL | This is used to create the block mesh and extract the 3D surface with snappyHexMesh for the CFD test
    echo "--------------------
    Stage #1 Mesh Check/Generation
--------------------"    
    # check if a mesh already exits, or if needs to re-generate
    mesh_dir=constant/polyMesh
    if [ -d "./${mesh_dir}" ] && [ -f "./${mesh_dir}/points.gz" ] && [ -f "./meshStats/log.mirrorMesh" ]
    then
        echo "Looks like mesh already exists!"
        echo "Checking mesh ..."
        points_in_log=$(cat meshStats/log.mirrorMesh | awk '/^Mirroring points/ { print $8 }')
        points_in_const=$(less ${mesh_dir}/pointLevel.gz | grep "(" -B 1 | awk 'NR==1')
        #points_in_const=$(zgrep "(" -B 1 ${mesh_dir}/pointLevel.gz | awk 'NR==1')
        points_min=40000000 
        # keeping a tolerance of 1% => points_min * 1.01 = 41068727.06
        points_tolerance=41062727
        if [[ $points_in_log -eq $points_in_const ]] && [[ $points_in_const -lt $points_tolerance ]] && [[ $points_in_const -gt $points_min ]]
        then 
            echo "Mesh is Ok." 
            echo "Skipping mesh generation (./AllmeshL) and moving on to the next stage!"
        else
            echo "Mesh check Failed!"
            if [[ $RUN_ONLY -eq 0 ]] 
            then
                echo " Cleaning older/currupt mesh files that may exist, before starting mesh generation. 
********************************************
NOTE: This stage can take >30mins!!
********************************************"
                rm -rf ${mesh_dir} meshStats/log.*
                generateMesh
            else 
                echo "Either the mesh is not properly generated or the files are corrupt."
                echo "It is recommended that you clean the case dir with: "
                echo "         \$ rm -rf ${mesh_dir} meshStats/log.* "
                echo "and regenerate the mesh."
                echo "Exiting ..."
                exit 1
            fi
        fi
    else
        if [[ $RUN_ONLY -eq 0 ]] 
        then
            echo "Running the AllmeshL script. Check progress in the log files generated. 
********************************************
    NOTE: This stage can take >30mins!!
********************************************"
            rm -rf ${mesh_dir} meshStats/log.*
            generateMesh
        else
            echo "
Error: no ${mesh_dir} exists in HPC_Benchmark/${benchmark_case}.
       Remove -r flag and re-run this script to generate the mesh with ./AllmeshL."
            exit 1
        fi
    fi

    if [[ ${MESH_ONLY} -eq 1 ]]
    then 
        echo "Executing with --gen-mesh-only. Will skip running the solvers."
        echo "Exiting now ... "
        exit 1
    fi

}

function run()
{
    echo "--------------------
    Stage #2 Running the benchmark 
--------------------"
    # configure MPI executable
    MPIEXEC_OPTIONS=""
    APP_PAR_OPTIONS=""

    # helper scripts for affinity
    HELPER_SCRIPT=helper.sh
    if [ ${platform} = CUDA ]
    then
        HELPER_SCRIPT=helper-cuda.sh
    fi
    if [[ $MPI_RANKS -gt 1 ]]; then
        MPIEXEC_OPTIONS="mpirun -np ${MPI_RANKS} --bind-to none ${CDIR}/${HELPER_SCRIPT}"
        APP_PAR_OPTIONS="-parallel"
        #2. decomposePar | This is used to decompose the 3D mesh into subdomains for parallel processing if >1ranks
        sed -i -e "s|numberOfSubdomains.*|numberOfSubdomains ${MPI_RANKS};|g" ./system/decomposeParDict
        if [ ${platform} = ROCR ]
        then
            export ${platform}_VISIBLE_DEVICES=" "
        fi
        decomposePar -force 2>&1 | tee log.decomposePar-${MPI_RANKS}-ranks-${NGPUS}-${SUFFIX}
        if [ ${platform} = ROCR ]
        then
            unset ${platform}_VISIBLE_DEVICES
        fi
        # ensure that the helper script has the NGPUs set properly
        sed -i -e "s|let NUM_GPUS=.*|let NUM_GPUS=${NGPUS}|g" ${CDIR}/${HELPER_SCRIPT}
    fi
    #setup env
    if [[ $NGPUS -eq 1 ]]; then
        export ${platform}_VISIBLE_DEVICES=0
        if [[ $MPI_RANKS -eq 1 ]]; then
            Numa_nodes=$(lscpu | awk '/^NUMA node\(s\)/{ print $3 }')
            Cores_per_numa=$(($MAX_CORES/$Numa_nodes))
            if [ ${platform} = CUDA ]
            then
                Numa_affinity_GPU0=$(nvidia-smi topo -m | grep GPU0 | awk 'NR==2 { print $12 }')
                myGPU0=$CUDA_VISIBLE_DEVICES
            else
                Numa_affinity_GPU0=$(rocm-smi --showtopo | grep "(Topology) Numa Node:" | awk -v pattern="0" '$1~pattern { print $6 }')
                myGPU0=$ROCR_VISIBLE_DEVICES
            fi
            cpu_start=$(($Numa_affinity_GPU0*$Cores_per_numa))
            cpu_forOS=1
            cpu_stop=$(($cpu_start + ${OMP_NUM_THREADS}*1 - 1 + ${cpu_forOS}))
            export GOMP_CPU_AFFINITY=$cpu_start-$cpu_stop:1
            echo -e "Local Rank = 0\tGOMP_CPU_AFFINITY = "$GOMP_CPU_AFFINITY"\t NUMA Node = "$Numa_affinity_GPU0"\t${platform}_VISIBLE_DEVICES = "$myGPU0
        fi
    fi
    #3. potentialFoam -writephi | This is used to evaluate and write the phi field for the CFD test
    ${MPIEXEC_OPTIONS} potentialFoam -writephi ${APP_PAR_OPTIONS} 2>&1 | tee log.potentialFoam-${MPI_RANKS}-ranks-${NGPUS}-${SUFFIX}
    #4. simpleFoam  | This is the solver that that is used in this benchmark.
    ${MPIEXEC_OPTIONS} ${app} ${APP_PAR_OPTIONS} 2>&1 | tee log.${app}-${MPI_RANKS}-ranks-${NGPUS}-${SUFFIX}
    #unset env
    if [[ $NGPUS -eq 1 ]]; then 
        unset ${platform}_VISIBLE_DEVICES
        if [[ $MPI_RANKS -eq 1 ]]; then
            unset GOMP_CPU_AFFINITY
        fi
    fi 
}

function printFOM()
{
    #1. foamLog | This extracts the relevant KPIs (e.g. Execution time, residuals, etc.)
    foamLog log.${app}-${MPI_RANKS}-ranks-${NGPUS}-${SUFFIX}
    #2. copy the logs for future
    cp -r logs logs-${MPI_RANKS}-ranks-${NGPUS}-${SUFFIX}-${now}
    EXEC_TIME=$(cat logs-${MPI_RANKS}-ranks-${NGPUS}-${SUFFIX}-${now}/executionTime_0 | awk -v pat="$END_TIME" '$1~pat { print $2 }')
    TIME_PER_STEP=$(echo "scale=2; $EXEC_TIME - $(cat logs-${MPI_RANKS}-ranks-${NGPUS}-${SUFFIX}-${now}/executionTime_0 | awk -v pat="$PREV_TIME" '$1~pat { print $2 }')" | bc)
    #3. print FOMs
    echo "--------------------
    FOMs:
--------------------
    1. Execution Time     (s): ${EXEC_TIME}
    2. Time per Time-Step (s): ${TIME_PER_STEP} 
-------------------"
}

function clean()
{
    # Source tutorial run functions
    . $WM_PROJECT_DIR/bin/tools/RunFunctions

    # Lets run the 3D Lid-driven cavity benchmark (M) case using the folloring commands:
    cd HPC_Benchmark/${benchmark_case}
    if [ ! -x Allrun ] && [ ! -x Allclean ] && [ ! -x AllmeshS ]
    then
        chmod +x All*
    fi
    ./Allclean
    rm -rf processor*
}

function usage()
{
    echo "

This script is designed to setup and run OpenFOAM ${benchmark_case} benchmark on GPUs.
=================================
usage: $0

       -h | --help      Prints the usage
       -c | --clean     Clean the case directory
       -d | --device    Specify target to offload to CUDA or HIP (default: HIP)
       -g | --ngpus     #GPUs to be used (between 1-4), defaults to 1
       -j | --threads   #OpenMP threads (default: 1)
       -n | --mpi-ranks #MPI ranks to be used. (default ranks=gpus)
       -l | --log-suffix user-defined name/suffix to add to logs (default: apu)
       -t | --time-steps #time-steps to run for (default: 20) 
       -r | --run-only  skip mesh build, and directly run the case
       --gen-mesh-only  Only build the mesh and skip running the case

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
            -c|--clean)
                clean
                exit 1
                ;;
            -d|--device)
                DEVICE="$2"
                shift 2
                ;;
            -g|--ngpus)
                NGPUS="$2"
                shift 2
                ;;
            -j|--threads)
                OMP_THREADS="$2"
                shift 2
                ;;
            -l|--log-suffix)
                SUFFIX="$2"
                shift 2
                ;;
            -n|--mpi-ranks)
                MPI_RANKS="$2"
                shift 2
                ;;
            -t|--time-steps)
                TIME_STEPS="$2"
                shift 2
                ;;
            -r|--run-only)
                RUN_ONLY=1
                shift 1
                ;;
            --gen-mesh-only)
                MESH_ONLY=1
                shift 1
                ;;
            -*|--*=|*) # unsupported flags
                echo "Error: Unsupported flag $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${NGPUS+x}" ]]; then
        NGPUS=1
        echo "Using default $NGPUS APU for this benchmark"
    fi

    if [[ -z "${DEVICE+x}" ]]; then
        DEVICE=HIP
    fi

    if [[ -z "${SUFFIX+x}" ]]; then
        SUFFIX=apu
    fi

    if [[ -z "${OMP_THREADS+x}" ]]; then
        OMP_THREADS=1
    fi

    if [[ -z "${MPI_RANKS+x}" ]]; then
        MPI_RANKS=$NGPUS
    fi
    
    if [[ -z "${TIME_STEPS+x}" ]]; then
        TIME_STEPS=20
    fi
    
    if [[ -z "${RUN_ONLY+x}" ]]; then
        RUN_ONLY=0
    fi

    if [[ -z "${MESH_ONLY+x}" ]]; then
        MESH_ONLY=0
    fi
}

#*******************************************************
#
# This is the Main part of this bash script which calls
# the functions above based on user choices
#
#*******************************************************


parse_args $*
setup
checkMesh
run
printFOM

#
# End of file
# Author: Suyash Tandon

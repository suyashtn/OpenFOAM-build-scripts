#!/bin/bash

function systemCheck()
{
    # Grab information about CPU cores
    Socket=$(lscpu | awk '/^Socket\(s\)/{ print $2 }')
    Cores_per_socket=$(lscpu | awk '/^Core\(s\) per socket/{ print $4 }')
    Cores=$(( $(lscpu | awk '/^Socket\(s\)/{ print $2 }') * $(lscpu | awk '/^Core\(s\) per socket/{ print $4 }') ))
    
    # Grab information about NUMA
    Numa_nodes=$(lscpu | awk '/^NUMA node\(s\)/{ print $3 }')
    Cores_per_numa=$(( $Cores / $Numa_nodes ))

    # Grab information about devices/accelerators
    Num_devices=$(rocminfo | grep "amdgcn-amd-amdhsa--" | wc -l)
    # List the NUMA affinity of each GPU#id in a list
    # On parrypeak this should sort of yield Gpu_numa_affinity_list=(2 3 0 1)
    # which should read as GPU0 has affinity to NUMA node 2, and so on.
    Gpu_numa_affinity_list=()
    # Also, sometimes NUMA affinity is screwed up and all GPUs are not evenly distributed.
    # Thus we attempt to find, Number of NUMA nodes with GPUs/devices in them
    Numa_nodes_wGPUs=1
    for ((idx = 0; idx < ${Num_devices}; idx++))
    do
        IDX=$(rocm-smi --showtoponuma | grep "GPU\[$idx" | awk 'NR==1 {print $6}')
        Gpu_numa_affinity_list=("${Gpu_numa_affinity_list[@]}" "$IDX")
        if [ $idx -gt 0 ] && [ ${Gpu_numa_affinity_list[$(($idx-1))]} -ne ${Gpu_numa_affinity_list[$idx]} ]
        then
            Numa_nodes_wGPUs=$(( $Numa_nodes_wGPUs + 1 ))
        fi
    done
    # Lets find the max. NUMA node number to ensure we are not going out of bounds
    # This will allow us to correctly set up the start and stop counts of the CPUs
    Gpu_numa_affinity_list_max=${Gpu_numa_affinity_list[0]}
    for n in "${Gpu_numa_affinity_list[@]}" ; do
        ((n > Gpu_numa_affinity_list_max)) && Gpu_numa_affinity_list_max=$(( $n+1 ))
    done
    if [[ $Gpu_numa_affinity_list_max -gt $Numa_nodes ]]; then
     echo "ERROR: Something is wrong with the NUMA affinity, and setup.
       Please check your system config again. Exiting..."
       exit 1
    fi
    # Find number of GPUs/accelerators on each NUMA node.
    # this assumes that the GPUs/accelerators are evenly distributed.
    Ngus_perNuma=$(( $Num_devices/$Numa_nodes_wGPUs )) 
}

function inputCheck()
{
    # Check any user inputs for accelerators
    if [ -z "${NUM_GPUS}" ]; then
        let NUM_GPUS=$Num_devices
    fi

    if [ -z "${GPU_STRIDE}" ]; then
        let GPU_STRIDE=1
    fi

    if [ -z "${GPU_START}" ]; then
        let GPU_START=0
        Available_devices=$(( ($Num_devices - $GPU_START) / $GPU_STRIDE ))
        if [[ $NUM_GPUS -gt $Available_devices ]]; then
            if [ $OMPI_COMM_WORLD_LOCAL_RANK -eq 0 ]; then
            echo " ======================================================================
 WARNING: After skipping first $GPU_START devices, with stride $GPU_STRIDE, only $Available_devices devices 
          are available. Cannot meet the requested $NUM_GPUS GPUs. 
          Will instead use $Available_devices GPUs for run!
 ======================================================================"
            fi
            NUM_GPUS=$Available_devices
        fi
    fi
    
    if [ -z "${OMP_STRIDE}" ]; then
        let OMP_STRIDE=1
    fi

    if [ -z "${RANK_STRIDE}" ]; then
        Cores_requested=$(( $NUM_GPUS * $Cores_per_numa / ${Ngus_perNuma} ))
        let RANK_STRIDE=$Cores_requested/${OMPI_COMM_WORLD_LOCAL_SIZE}
    fi

    if [ -z "${CPU_SHIFT}" ]; then
        let CPU_SHIFT=0
    fi

    if [ -z "${CPU_FOR_OS}" ]; then
    let CPU_FOR_OS=0
    fi
}

function setupAffinity()
{
    # Evaluate how many ranks to be distributed to each device
    let ranks_per_gpu=$(((${OMPI_COMM_WORLD_LOCAL_SIZE}+${NUM_GPUS}-1)/${NUM_GPUS}))
    
    # Evaluate GPU #id for each rank
    let my_gpu=$(($OMPI_COMM_WORLD_LOCAL_RANK*$GPU_STRIDE/$ranks_per_gpu))+${GPU_START}

    # Evaluate local rank per device
    if [[ $ranks_per_gpu -gt 1 ]]
    then 
        if [[ $Ngus_perNuma -gt 1 ]]
        then
            local_rank_per_gpu=$(( $OMPI_COMM_WORLD_LOCAL_RANK % ${Cores_per_numa} ))
        else
            local_rank_per_gpu=$(( $OMPI_COMM_WORLD_LOCAL_RANK % ${ranks_per_gpu} ))
        fi
    else
        local_rank_list=(0)
        for ((i = 1; i < ${Num_devices}; i++))
        do
            if [ ${Gpu_numa_affinity_list[$(($i-1))]} -eq ${Gpu_numa_affinity_list[$i]} ]
            then
                entry=$(( ${local_rank_list[$(($i-1))]} + 1 ))
            else
                entry=0
            fi
            local_rank_list=("${local_rank_list[@]}" "${entry}")
        done
        local_rank_per_gpu=${local_rank_list[${my_gpu}]}
    fi

    # Evaluate the start and stop positions (including OMP threads) for each rank
    let cpu_start=$(($Cores_per_numa*${Gpu_numa_affinity_list[${my_gpu}]}))+$(($RANK_STRIDE*${local_rank_per_gpu}))+${CPU_SHIFT}
    let cpu_stop=$(($cpu_start+$OMP_NUM_THREADS*$OMP_STRIDE-1))+${CPU_FOR_OS}

    # Total CPUs needed = stop-start
    # To check if MPI size is more than available (with NGPUs and RANK_STRIDE): 
    # if (MPI_Size (1+cpus_needed) > Cores_requested); then exit; else continue.
    cpus_needed=$(( $cpu_stop - $cpu_start + 1))
    # Evaluate avail cores = Cores_req/(1+cpus_needed). Note 1 was already added above.
    available_cores=$(( $Cores_requested/$cpus_needed ))
    
    if [ ${OMPI_COMM_WORLD_LOCAL_SIZE} -gt $available_cores ]; then
        echo "ERROR: Based on your configuration, cannot run with more than $available_cores ranks.
       Please check your setup - NUM_GPUS, RANK_STRIDE in this script. 
        
       Exiting..."
        exit 1
    fi
    
    export GOMP_CPU_AFFINITY=$cpu_start-$cpu_stop:$OMP_STRIDE
    # export OMP_PLACES="{$cpu_start:$OMP_NUM_THREADS:$OMP_STRIDE}"

    # export ROCR_VISIBLE_DEVICES=${Gpu_numa_affinity_list[${my_gpu}]}
    export ROCR_VISIBLE_DEVICES=${my_gpu}
}

function printAffinity()
{
    # eval "taskset --cpu-list ${cpu_start}-${cpu_stop} $*"

    echo -e "Local Rank = "$OMPI_COMM_WORLD_LOCAL_RANK"\tGOMP_CPU_AFFINITY = "$GOMP_CPU_AFFINITY"\t NUMA Node = "${Gpu_numa_affinity_list[${my_gpu}]}"\tROCR_VISIBLE_DEVICES = "$ROCR_VISIBLE_DEVICES
    # echo -e "Local Rank = "$OMPI_COMM_WORLD_LOCAL_RANK"\tOMP_PLACES = "$OMP_PLACES"\t NUMA Node = "${Gpu_numa_affinity_list[${my_gpu}]}"\tROCR_VISIBLE_DEVICES = "$ROCR_VISIBLE_DEVICES
}

function printVars()
{
    echo "============================================"
    echo -e "Core \t\t\t: $Cores"
    echo -e "Socket \t\t\t: $Socket"
    echo -e "Cores_per_socket \t: ${Cores_per_socket}"
    echo -e "Numa Nodes \t\t: ${Numa_nodes}"
    echo -e "Cores_per_Numa \t\t: ${Cores_per_numa}"
    echo -e "Num_devices \t\t: ${Num_devices}"
    echo -e "Numa nodes w GPUs \t: ${Numa_nodes_wGPUs}"
    echo -e "NGPUs per NUMA \t\t: ${Ngus_perNuma}"
    echo -e "Available Devices \t: ${Available_devices}"
    echo -e "Cores Requested \t: ${Cores_requested}"
    echo -e "Rank Stride \t\t: ${RANK_STRIDE}"
    echo -e "ranks_per_gpu \t\t: ${ranks_per_gpu}"
    echo -e "available cores \t: ${available_cores}"
    echo -e "GPU Numa Affinity List \t: ${Gpu_numa_affinity_list[*]}"
    echo "============================================"
}

function profilePerRank()
{
    # Add a date/timestamp to distinguish the profiles
    now=$(date +'%m%d%Y')

    prof_name=motorbike_simple_${now}
    eval "${ROCM_PATH}/bin/rocprof --hsa-trace  --roctx-trace   -d ./rocprof/${prof_name}.${OMPI_COMM_WORLD_RANK} -o ./rocprof/${prof_name}.${OMPI_COMM_WORLD_RANK}/${prof_name}.${OMPI_COMM_WORLD_RANK}.csv $*"
}

systemCheck
inputCheck
setupAffinity
printAffinity
# wait
# sleep 3
# if [[ $OMPI_COMM_WORLD_LOCAL_RANK -eq 0 ]]; then
#     printVars
# fi
# profilePerRank

$@

#
# End of file
# Author: Suyash Tandon

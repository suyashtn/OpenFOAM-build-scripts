#!/bin/bash
# 
cd ${0%/*} || exit 1    # Run from this directory
CDIR=`pwd`

function setup()
{
    # Device ID
    MAX_DEVICES=$(rocminfo | grep "amdgcn-amd-amdhsa--" | wc -l)

    if [[ ${GPU_ID} -lt 0 ]] ||  [[ ${GPU_ID} -gt ${MAX_DEVICES} ]]; then  
        # ERR condition
        echo " ERROR: The device ID# is outside of the permissible rangec[0-${MAX_DEVICES}]"
        echo "        Check the device ID used, and run again!"
        exit 1
    fi
    
    # Collect NSAMPLES
    if [[ ${NSAMPLES} -le 0 ]];then
        # ERR condition
        echo " ERROR: Invalid number of samples requested. Please check nsamples count and run again!"
        exit 1
    fi

    # Start timer
    start=$(date +"%s%N")

    # date + timestamp for output log
    now=$(date +'%m%d%Y')

    # Check if powerLogs/ dir exists to create power log
    if [ ! -d ${CDIR}/powerLogs ]; then
        mkdir -p ${CDIR}/powerLogs
    fi
}

function collect_power()
{
    for i in $(seq 1 $NSAMPLES); do
        #write the time in nano-sec
        end=$(( $(date +"%s%N") - $start ))
        #write the power usage for dev 0
        power=$(rocm-smi -d ${GPU_ID} --showpower | awk 'NR==5 {print $8}')
        #write to out file
        if [[ $i -eq 1 ]]; then
            printf "%-10s %-15s %-15s\n" "NSAMPLES" "TIME [ns]" "Power [W]"  2>&1 | tee --append ${CDIR}/powerLogs/${OUT_FILE}-${now}
            echo "-----------------------------------------------------" 2>&1 | tee --append ${CDIR}/powerLogs/${OUT_FILE}-${now}
        fi
        printf "%-10s %-15s %-15s\n" "$i" "${end}" "${power}"  2>&1 | tee --append ${CDIR}/powerLogs/${OUT_FILE}-${now}
        # echo -e $i "\t" ${end} "\t" ${power} 2>&1 | tee --append ${CDIR}/powerLogs/${OUT_FILE}-${now}
    done

}

function usage()
{
    echo "

This script is designed to setup and run OpenFOAM ${benchmark_case} benchmark on GPUs.
=================================
usage: $0

       -h | --help      Prints the usage
       -d | --device    Collect power from a specific device (Default: 0)
       -n | --nsamples  Number of samples to collect (Default: 500)
       -o | --output    Log and collect the Power (W) drawn from the device 
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
            -d|--device)
                GPU_ID="$2"
                shift 2
                ;;
            -n|--nsamples)
                NSAMPLES="$2"
                shift 2
                ;;
            -o|--output)
                OUT_FILE="$2"
                shift 2
                ;;
            -*|--*=|*) # unsupported flags
                echo "Error: Unsupported flag $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${GPU_ID+x}" ]]; then
        GPU_ID=0
    fi

    if [[ -z "${NSAMPLES+x}" ]]; then
        NSAMPLES=500
    fi
    
    if [[ -z "${OUT_FILE+x}" ]]; then
        OUT_FILE="log.power"
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
collect_power

echo " "
echo "Power collection complete!"
echo "done."

#EOF
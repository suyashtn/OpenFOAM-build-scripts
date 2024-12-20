#!/bin/bash

# Script to scrape FOM from OpenFOAM benchmarks

CDIR=`pwd`

function checkDir()
{
    #1. check if dir exits
    if [[ -d ${DIR} ]];then
        cd ${DIR}
        echo "${DIR}"
        scrapeFOM
    else
        echo " "
        echo "ERROR: ${DIR} does not exist! "
        echo "Exiting..."
        exit 0
    fi
}


function scrapeFOM()
{
    #1. Calculate times
    PREV_TIME=$(( $END_TIME - 1 ))
    #2. check if there are dirs with name "logs" 
    NUM_LOGS=$(find . -type d -iname "*logs*" | wc -l)
    if [ $NUM_LOGS -eq 0 ]; then
       echo " "
       echo "Looks like no logs to scrape. Rerun foamLog to generate logs."
       echo "Exiting..."
       exit 0
    fi
    #3. cycle through the logs
    filename=$(basename ${DIR})
    fomfile=${DIR}/log.FOM-${filename}
    echo "--------------------" > ${fomfile}
    echo "FOM: " >> ${fomfile}
    echo "--------------------" >> ${fomfile}
    printf "%-50s %-15s %-15s\n" "LOG_FILE" "EXEC_TIME [s]" "TIME PER STEP [s]" >> ${fomfile}
    for ((num=1; num<=${NUM_LOGS}; num++))
    do
        log_dir=$(find . -type d -iname "*logs*" -print | awk "NR==$num")
        cd ${log_dir}
        #pwd
        EXEC_TIME=$(cat executionTime_0 | awk -v pat="$END_TIME" '$1~pat { print $2 }')
        TIME_PER_STEP=$(echo "scale=2; $EXEC_TIME - $(cat executionTime_0 | awk -v pat="$PREV_TIME" '$1~pat { print $2 }')" | bc)
        #3. print FOMs
        printf "%-50s %-15s %-15s\n" "$log_dir" "${EXEC_TIME}" "${TIME_PER_STEP}" >> ${fomfile}
        #echo -e "LOG: "${log_dir}"\t EXEC_TIME [s] = "${EXEC_TIME}"\t TIME PER STEP[s] = "${TIME_PER_STEP} >> ${fomfile}
        cd ${DIR}
    done
    #4. print the FOM file on screen
    cat $fomfile
}

function usage()
{
    echo "

This script is designed to scape FOM.
=================================
usage: $0 -d <path/to/dir>

       -h | --help      Prints the usage
       -d | --dir       Specify the dir where to scrape the FOM from
       -t | --time      End time to scrape the logs (Default: t=20)

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
            -d|--dir)
                DIR="$2"
                shift 2
                ;;
            -t|--time)
                END_TIME="$2"
                shift 2
                ;;
            -*|--*=|*) # unsupported flags
                echo "Error: Unsupported flag $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${DIR+x}" ]]; then
        echo "No input directory provided!..."
        usage
        exit 0
    fi

    if [[ -z "${END_TIME+x}" ]];then
        END_TIME=20
    fi

}

#*******************************************************
#
# This is the Main part of this bash script which calls
# the functions above based on user choices
#
#*******************************************************


parse_args $*
checkDir
#printFOM
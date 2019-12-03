#!/bin/bash
# set -x
RED='\033[0;31m'
GRN='\033[0;32m'
NC='\033[0m' # No Color

usage()
{
    echo ""
    echo "  Usage: ./run.sh WORKLOAD TESTSIZE [PATCH]"
    echo ""
    echo "    WORKLOAD:   The workload to test."
    echo "    TESTSIZE:   The size of workload to test. Usually 10 will be sufficient for reproducing all bugs."
    echo "    PATCH:      The name of the patch that reproduces bugs for WORKLOAD. If not specfied, then we test the original program without bugs."
    echo ""
}


# Workload
WORKLOAD=$1
# Sizes of the workloads
TESTSIZE=$2
# patchname
PATCH=$3

# PM Image file
PMIMAGE=/mnt/pmem0/${WORKLOAD}
TEST_ROOT=/home/wiper_nvdimm

# variables to use
PMRACE_EXE=${TEST_ROOT}/pmrace/build/app/pmrace
PINTOOL_SO=${TEST_ROOT}/pmrace/pintool/obj-intel64/pintool.so
DATASTORE_EXE=${TEST_ROOT}/workloads/hashmap/data_store
PIN_EXE=${TEST_ROOT}/pin-3.10/pin

TIMING_OUT=${WORKLOAD}_time.txt
DEBUG_OUT=${WORKLOAD}_${TESTSIZE}_debug.txt

if ! [[ $TESTSIZE =~ ^[0-9]+$ ]] ; then
   echo -e "${RED}Error:${NC} Invalid workload size ${TESTSIZE}." >&2; usage; exit 1
fi

if [[ ${WORKLOAD} =~ ^(btree|ctree|rbtree)$ ]]; then
    if [[ ${PATCH} != "" ]]; then
        PATCH_LOC=${TEST_ROOT}/asplos20-submission/patch/${WORKLOAD}_${PATCH}.patch
        echo "Applying bug patch: ${WORKLOAD}_${PATCH}.patch."
        cd ${TEST_ROOT}/pmdk && git apply ${PATCH_LOC} && cd ${TEST_ROOT}/pmrace || exit 1
    fi
elif [[ ${WORKLOAD} =~ ^(hashmap_atomic|hashmap_tx)$ ]]; then
    if [[ ${PATCH} != "" ]]; then
        PATCH_LOC=${TEST_ROOT}/asplos20-submission/patch/${WORKLOAD}_${PATCH}.patch
        echo "Applying bug patch: ${WORKLOAD}_${PATCH}.patch."
        cd ${TEST_ROOT}/pmdk && git apply ${PATCH_LOC} && cd ${TEST_ROOT}/pmrace || exit 1
    fi
else
    echo -e "${RED}Error:${NC} Invalid workload name ${WORKLOAD}." >&2; usage; exit 1
fi

echo Running ${WORKLOAD}. Test size = ${TESTSIZE}.

# Generate config file
CONFIG_FILE=${WORKLOAD}_${TESTSIZE}_config.txt
rm -f ${CONFIG_FILE}
echo "PINTOOL_PATH ${PINTOOL_SO}" >> ${CONFIG_FILE}
echo "EXEC_PATH ${DATASTORE_EXE}" >> ${CONFIG_FILE}
echo "PM_IMAGE ${PMIMAGE}" >> ${CONFIG_FILE}
echo "PRE_FAILURE_COMMAND ${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} ${TESTSIZE}" >> ${CONFIG_FILE}
echo "POST_FAILURE_COMMAND ${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} 2" >> ${CONFIG_FILE}

# Remove old pmimage and fifo files
rm -f /mnt/pmem0/*
rm -f /tmp/*fifo
rm -f /tmp/func_map

echo "Recompiling workload, suppressing make output."
make -C ${TEST_ROOT}/pmdk > /dev/null 2>&1
make clean -C ${TEST_ROOT}/workloads/hashmap > /dev/null 2>&1
make -C ${TEST_ROOT}/workloads/hashmap > /dev/null 2>&1

# unapply patch
if [[ $PATCH != "" ]]; then
    echo "Reverting patch: ${WORKLOAD}_${PATCH}.patch."
    cd ${TEST_ROOT}/pmdk && git apply -R ${PATCH_LOC} && cd ${TEST_ROOT}/pmrace || exit 1
fi

MAX_TIMEOUT=2000

# Init the pmImage
${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} ${TESTSIZE}
#${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} 1
# Run realworkload
# Start PMRace
echo -e "${GRN}Info:${NC} We kill the post program after running some time, so don't panic if you see a process gets killed."
timeout ${MAX_TIMEOUT} ${PMRACE_EXE} ${CONFIG_FILE} > ${TIMING_OUT} 2> ${DEBUG_OUT} &
sleep 1
timeout ${MAX_TIMEOUT} ${PIN_EXE} -t ${PINTOOL_SO} -o pmrace.out -t 1 -f 1 -- ${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} ${TESTSIZE} > /dev/null
wait


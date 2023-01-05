#!/bin/bash -e

WORKLOAD=${WORKLOAD:-iperf}

# general parameters
IPERF_VER=${1:-2}
PROTOCOL=${2:-TCP}
MODE=${3:-pod2pod}

# server parameters
SERVER_POD_PORT=${SERVER_POD_PORT:-5201}
SERVER_CORE_COUNT=${SERVER_CORE_COUNT:-1}
SERVER_CORE_LIST=${SERVER_CORE_LIST:-"-1"}
SERVER_OPTIONS=${SERVER_OPTIONS:-""}

# server service parameters
IPERF_SERVICE_NAME=${IPERF_SERVICE_NAME:-iperf-server-service}

# client parameters
CLIENT_CORE_COUNT=${CLIENT_CORE_COUNT:-1}
CLIENT_CORE_LIST=${CLIENT_CORE_LIST:-"-1"}
PARALLEL_NUM=${PARALLEL_NUM:-1}
CLIENT_TRANSMIT_TIME=${CLIENT_TRANSMIT_TIME:-30}
if [[ $PROTOCOL == TCP ]]; then
  BUFFER_SIZE=${BUFFER_SIZE:-128K}
else
  BUFFER_SIZE=${BUFFER_SIZE:-1470}
fi
UDP_BANDWIDTH=${UDP_BANDWIDTH:-50M}
CLIENT_OPTIONS=${CLIENT_OPTIONS:-""}
ONLY_USE_PHY_CORE=${ONLY_USE_PHY_CORE:-yes}

# Logs Setting
DIR="$( cd "$( dirname "$0" )" &> /dev/null && pwd )"
. "$DIR/../../script/overwrite.sh"

# Workload Setting
WORKLOAD_PARAMS=(IPERF_VER MODE SERVER_POD_PORT SERVER_CORE_COUNT SERVER_CORE_LIST SERVER_OPTIONS IPERF_SERVICE_NAME PROTOCOL CLIENT_CORE_COUNT CLIENT_CORE_LIST PARALLEL_NUM CLIENT_TRANSMIT_TIME BUFFER_SIZE UDP_BANDWIDTH CLIENT_OPTIONS ONLY_USE_PHY_CORE)

DOCKER_OPTIONS="-e WORKLOAD=$WORKLOAD -e IPERF_VER=$IPERF_VER -e MODE=$MODE -e SERVER_POD_PORT=$SERVER_POD_PORT -e SERVER_CORE_COUNT=$SERVER_CORE_COUNT -e SERVER_CORE_LIST=$SERVER_CORE_LIST -e SERVER_OPTIONS=$SERVER_OPTIONS -e IPERF_SERVICE_NAME=$IPERF_SERVICE_NAME -e PROTOCOL=$PROTOCOL -e CLIENT_CORE_COUNT=$CLIENT_CORE_COUNT -e CLIENT_CORE_LIST=$CLIENT_CORE_LIST -e PARALLEL_NUM=$PARALLEL_NUM -e CLIENT_TRANSMIT_TIME=$CLIENT_TRANSMIT_TIME -e BUFFER_SIZE=$BUFFER_SIZE -e UDP_BANDWIDTH=$UDP_BANDWIDTH -e CLIENT_OPTIONS=$CLIENT_OPTIONS -e ONLY_USE_PHY_CORE=$ONLY_USE_PHY_CORE"

# Kubernetes Setting
RECONFIG_OPTIONS="-DWORKLOAD=$WORKLOAD -DIPERF_VER=$IPERF_VER -DMODE=$MODE -DSERVER_POD_PORT=$SERVER_POD_PORT -DSERVER_CORE_COUNT=$SERVER_CORE_COUNT -DSERVER_CORE_LIST=$SERVER_CORE_LIST -DSERVER_OPTIONS=$SERVER_OPTIONS -DIPERF_SERVICE_NAME=$IPERF_SERVICE_NAME -DPROTOCOL=$PROTOCOL -DCLIENT_CORE_COUNT=$CLIENT_CORE_COUNT -DCLIENT_CORE_LIST=$CLIENT_CORE_LIST -DPARALLEL_NUM=$PARALLEL_NUM -DCLIENT_TRANSMIT_TIME=$CLIENT_TRANSMIT_TIME -DBUFFER_SIZE=$BUFFER_SIZE -DUDP_BANDWIDTH=$UDP_BANDWIDTH -DCLIENT_OPTIONS=$CLIENT_OPTIONS -DONLY_USE_PHY_CORE=$ONLY_USE_PHY_CORE"

JOB_FILTER="job-name=iperf-server"

. "$DIR/../../script/validate.sh"
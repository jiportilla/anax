#!/bin/bash

# The purpose of this test is to verify that the DELETE /node API works correctly in a full
# runtime context. Some parts of this test simulate the fact that anax is configured to auto-restart
# when it terminates.

EXCH_URL="${EXCH_APP_HOST}"

if [ ${CERT_LOC} -eq "1" ]; then
  CERT_VAR="--cacert /certs/css.crt"
else
  CERT_VAR=""
fi

for (( ; ; ))
do

  # The node is already running, so start with the blocking form of the unconfig API. The API should always be
  # successful and should always be empty.
  echo "Unconfig node, blocking"
  DEL=$(curl -sSLX DELETE $ANAX_API/node)
  if [ $? -ne 0 ]
  then
    echo -e "Error return from DELETE: $?"
    exit 2
  fi
  if [ "$DEL" != "" ]
  then
    echo -e "Non-empty response to DELETE node: $DEL"
    exit 2
  fi

  # Following the API call, the node's entry in the exchange should have some changes in it. The messaging key should be empty,
  # and the list of registered microservices should be empty.
  NST=$(curl -sSL $CERT_VAR --header 'Accept: application/json' -u "e2edev@somecomp.com/e2edevadmin:e2edevadminpw" "${EXCH_URL}/orgs/$DEVICE_ORG/nodes/an12345" | jq -r '.')
  PK=$(echo "$NST" | jq -r '.publicKey')
  if [ "$PK" != "null" ]
  then
    echo -e "publicKey should be empty: $PK"
    exit 2
  fi

  RM=$(echo "$NST" | jq -r '.registeredServices[0]')
  if [ "$RM" != "null" ]
  then
    echo -e "registeredServices should be empty: $RM"
    exit 2
  fi

  # This part of the test is to ensure that anax actually terminates. We will give anax 2 mins to terminate which should be
  # much more time than it needs. Normal behavior should be termination in seconds.
  echo -e "Making sure old anax has ended."
  COUNT=1
  while :
  do
    # Wait for the "connection refused" message
    GET=$(curl -sSL "$ANAX_API/node")
    if [ $? -eq 7 ]; then
      break
    else
      echo -e "Is anax up yet: $GET"
      CS=$(echo "$GET" | jq -r '.configstate.state')
      if [ "$CS" == "unconfigured" ]; then
        break
      fi
    fi

    sleep 5

  done

  # Save off the existing log file, in case the next test fails and we need to look back to see how this
  # instance of anax actually ended.
  mv /tmp/anax.log /tmp/anax1.log

  # Simulate the auto-restart of anax and reconfig of the node.
  echo "Node unconfigured. Restart and reconfig node."

  ./apireg.sh
  if [ $? -ne 0 ]
  then
    echo "Node reconfig failed."
    TESTFAIL="1"
    exit 2
  fi

  # Wait a random length of time before issuing the DELETE /node again. This is to try to catch
  # anax in a state where it doesnt handle the shutdown correctly.
  t=$((1+ RANDOM % 90))
  echo -e "Sleeping $t now to make agreements"
  sleep $t

  # Log the current state of agreements and previous agreements before we unconfigure again.
  echo -e "Current agreements"
  ACT=$(curl -sSL $ANAX_API/agreement | jq -r '.agreements.active' | grep "current_agreement_id")
  echo $ACT

  echo -e "Previous terminations"
  ARC=$(curl -sSL $ANAX_API/agreement | jq -r '.agreements.archived' | grep "terminated_description" | awk '{print $0,"\n"}')
  echo $ARC

  # =======================================================================================================================
  # This is phase 2 of the main test loop. The node is already running, so this time use the non-blocking form of the
  # unconfig API. This form requires that we poll GET /node to figure out when unconfiguration is complete.
  echo "Unconfig node, non-blocking"
  DEL=$(curl -sSLX DELETE "$ANAX_API/node?block=false")
  if [ $? -ne 0 ]
  then
    echo -e "Error return from DELETE: $?"
    exit 2
  fi
  if [ "$DEL" != "" ]
  then
    echo -e "Non-empty response to DELETE node: $DEL"
    exit 2
  fi

  # Start polling for unconfig completion. Unconfig could take several minutes if we are running this test with a blockchain
  # configuration.
  echo -e "Polling anax API for completion of device unconfigure."
  COUNT=1
  while :
  do
    GET=$(curl -sSL "$ANAX_API/node")
    if [ $? -eq 7 ]; then
      break
    else
      echo -e "Is anax still up: $GET"

      CS=$(echo "$GET" | jq -r '.configstate.state')
      if [ "$CS" == "unconfigured" ]; then
        break
      fi
    fi

    sleep 5

  done

  # Following the API call, the node's entry in the exchange should have some changes in it. The messaging key should be empty,
  # and the list of registered microservices should be empty.
  NST=$(curl -sSL $CERT_VAR --header 'Accept: application/json' -u "e2edev@somecomp.com/e2edevadmin:e2edevadminpw" "${EXCH_URL}/orgs/$DEVICE_ORG/nodes/an12345" | jq -r '.')
  PK=$(echo "$NST" | jq -r '.publicKey')
  if [ "$PK" != "null" ]
  then
    echo -e "publicKey should be empty: $PK"
    exit 2
  fi

  RM=$(echo "$NST" | jq -r '.registeredServices[0]')
  if [ "$RM" != "null" ]
  then
    echo -e "registeredServices should be empty: $RM"
    exit 2
  fi

  # Save off the existing log file, in case the next test fails and we need to look back to see how this
  # instance of anax actually ended.
  mv /tmp/anax.log /tmp/anax1.log

  # Simulate the auto-restart of anax and reconfig of the node.
  echo "Node unconfigured. Restart and reconfig node."

  ./apireg.sh
  if [ $? -ne 0 ]
  then
    echo "Node reconfig failed."
    TESTFAIL="1"
    exit 2
  fi

  # Wait a random length of time before issuing the DELETE /node again. This is to try to catch
  # anax in a state where it doesnt handle the shutdown correctly.
  t=$((1+ RANDOM % 90))
  echo -e "Sleeping $t now to make agreements"
  sleep $t

  # Log the current state of agreements and previous agreements before we unconfigure again.
  echo -e "Current agreements"
  ACT=$(curl -sSL $ANAX_API/agreement | jq -r '.agreements.active' | grep "current_agreement_id")
  echo $ACT

  echo -e "Previous terminations"
  ARC=$(curl -sSL $ANAX_API/agreement | jq -r '.agreements.archived' | grep "terminated_description" | awk '{print $0,"\n"}')
  echo $ARC

done

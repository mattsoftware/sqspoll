#!/usr/bin/env bash

set -e

help(){
 cat << EOF
 Usage:
 $0 <options>
    -h         this help message
    -v         verbose output
    --timeout= sets the timeout to wait for new messages
    --queue=   sets the queue url
    --run=     the command to run (the body of the sqs message will be sent to stdin of this command)
    --count=   exit after x number of messages
    --loop=    exit after x number of timeouts
    --region=  specify the aws region for the queue url
    --msgs=    number of msgs to poll per request
EOF
}

for x in "$@"; do
    case $x in
        --help|-h|help)
            help
            exit
            ;;
        -v)
            VERBOSE=1
            ;;
        --timeout=*)
            TIMEOUT=$(echo $x | cut -d= -f2)
            ;;
        --region=*)
            AWS_REGION=$(echo $x | cut -d= -f2)
            ;;
        --queue=*)
            QUEUE_URL=$(echo $x | cut -d= -f2)
            ;;
        --run=*)
            RUN_CMD=$(echo $x | cut -d= -f2)
            ;;
        --count=*)
            COUNT=$(echo $x | cut -d= -f2)
            ;;
        --loop=*)
            LOOP=$(echo $x | cut -d= -f2)
            ;;
        --msgs=*)
            MSGS=$(echo $x | cut -d= -f2)
            ;;
    esac
done
: ${AWS_REGION:?"You must provide the AWS region with --region"}
: ${QUEUE_URL:?"You must provide a queue url with --queue"}
: ${RUN_CMD:?"You must provide a run command with --run"}
: ${VERBOSE:="0"}
: ${TIMEOUT:="10"}
: ${COUNT:=""}
: ${LOOP:=""}
: ${MSGS:="10"}

function log () {
    [[ $VERBOSE == 1 ]] && logerr $@
    return 0
}
function logerr () {
    (>&2 echo $@)
    return 0
}

set +e

log "Queue: $QUEUE_URL"
log "Timeout = $TIMEOUT"
while :; do
 MESSAGES=$(aws --region "$AWS_REGION" sqs receive-message --queue-url "$QUEUE_URL" --wait-time-seconds "$TIMEOUT" --max-number-of-messages $MSGS)
 if [[ "$MESSAGES" != "" ]]; then
  if [[ $COUNT != "" ]]; then
   let COUNT--
   log "Count: $COUNT"
   (( $COUNT < 1 )) && exit
  fi
  while read -r line ;do
   [[ "$line" == "" ]] && continue
      # Last line of a message
   if [[ "$line" == '},' ]] || [[ "$line" == ']' ]]; then
    SINGLEMESSAGE="$(echo "$SINGLEMESSAGE"; echo "$line")"
    RECEIPT=$(awk -F'"' '/ReceiptHandle/{print $4}' <<< "$SINGLEMESSAGE")
    log
    log "Receipt: $RECEIPT"
    log "Got Message:"
    log "$SINGLEMESSAGE"
    if (echo "$SINGLEMESSAGE" | "$RUN_CMD") > /dev/null 2>&1 ;then
     aws --region "$AWS_REGION" sqs delete-message --queue-url "$QUEUE_URL" --receipt-handle "$RECEIPT"
     logerr -n √
    else
     logerr -n X
     echo "$SINGLEMESSAGE" >> error/$(date +%s)
    fi
    unset  SINGLEMESSAGE
    continue
   fi
   SINGLEMESSAGE="$(echo "$SINGLEMESSAGE"; echo "$line")"
  done <<< "$MESSAGES"
 fi
 if [[ $LOOP != "" ]]; then
  let LOOP--
  log "Loop: $LOOP"
  (( $LOOP < 1 )) && exit
 fi
done

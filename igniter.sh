#!/bin/bash

# before running this script, the array below must be populated with
# all nodes pub keys that will be part of the route

declare pub_keys=(
     # first hop pub key (not yours)
     # next hop's pub key
     # next hop's pub key
     # next hop's pub key
     # next hop's pub key
     # next hop's pub key
     # next hop's pub key
     # your node's pub key
)

AMOUNT=1000000 # value in satoshis to transmit
OUTGOING_CHAN_ID= # initial channel to transmit from
MAX_FEE=100 # Max fee, in sats that you're prepared to pay.

####################################################
## the remaining of this script can remain untouched

# Join pub keys into single string at $HOPS
IFS=, eval 'HOPS="${pub_keys[*]}"'

# If an umbrel, use docker, else call lncli directly
LNCLI="lncli"
if uname -a | grep umbrel > /dev/null; then
    LNCLI="docker exec -i lnd lncli"
fi

# Arg option: 'build'
build () {
    until $LNCLI buildroute --amt ${AMOUNT} --hops ${HOPS} --outgoing_chan_id ${OUTGOING_CHAN_ID}
    do echo "Route build failed, retrying in 1 min."
       sleep 60
    done
}

# Arg option: 'send'
send () {
  INVOICE=$($LNCLI addinvoice --amt=${AMOUNT} --memo="Rebalancing...")

  PAYMENT_HASH=$(echo -n $INVOICE | jq -r .r_hash)
  PAYMENT_ADDRESS=$(echo -n $INVOICE | jq -r .payment_addr)
  
  ROUTE=$(build)
  FEE=$(echo -n $ROUTE | jq .route.total_fees_msat)
  FEE=${FEE:1:-4}
  
  echo "Route fee is $FEE sats."

  if (( FEE  > MAX_FEE )); then
    echo "Error: $FEE exceeded max fee of $MAX_FEE"
    exit 1
  fi

  echo $ROUTE \
    | jq -c "(.route.hops[-1] | .mpp_record) |= {payment_addr:\"${PAYMENT_ADDRESS}\", total_amt_msat: \"${AMOUNT}000\"}" \
    | $LNCLI sendtoroute --payment_hash=${PAYMENT_HASH} -
}

# Arg option: '--help'
help () {
    cat << EOF
usage: ./igniter.sh [--help] [build] [send]
       <command> [<args>]

Open the script and configure values first. Then run
the script with one of the following flags:

   build             Build the routes for the configured nodes
   send              Build route and send payment along route

EOF
}


# Run the script
all_args=("$@")
rest_args_array=("${all_args[@]:1}")
rest_args="${rest_args_array[@]}"

case $1 in
    "build" )
        build $rest_args
        ;;
    "send" )
        send $rest_args
        ;;
    "--help" )
        help
        ;;
    * )
        help
        ;;
esac

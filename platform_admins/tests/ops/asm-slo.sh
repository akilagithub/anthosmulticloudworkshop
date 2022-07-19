PROJECT_ID=${1:-${GOOGLE_PROJECT}}
NAMESPACE=${2:-ob-dev}

OAUTH_TOKEN=$(gcloud auth application-default print-access-token)
#SERVICE_NAMES=("checkoutservice")
#LATENCIES=("0.1s")
SERVICE_NAMES=("adservice" "cartservice" "checkoutservice" "currencyservice" "emailservice" "frontend" "paymentservice" "productcatalogservice" "recommendationservice" "shippingservice")
LATENCIES=("0.0025s" "0.1s" "0.1s" "0.003s" "0.004s" "0.075s" "0.0039s" "0.0015s" "0.01s" "0.002s")

for IDX in ${!SERVICE_NAMES[@]}
do
    # get the fully qualified service id
    FQ_SERVICE_ID=$(curl -s -H "Authorization: Bearer $OAUTH_TOKEN" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/services" | \
        jq -r ".services[] |  \
        select (.istioCanonicalService.canonicalServiceNamespace == \"${NAMESPACE}\" \
        and .istioCanonicalService.canonicalService == \"${SERVICE_NAMES[${IDX}]}\") \
        | .name")

    # get only the service id which is at the end
    # ex: projects/939333334266/services/canonical-ist:proj-939333334266-ob-redis-redis
    # extract 'canonical-ist:proj-...'
    SERVICE_ID=$(echo ${FQ_SERVICE_ID} | cut -d "/" -f4)

    LATENCY_SLO_POST=$(cat << EOF
{
"serviceLevelIndicator": {
    "basicSli": {
    "latency": {
        "threshold": "${LATENCIES[${IDX}]}"
    }
    }
},
"goal": 0.9,
"calendarPeriod": "DAY",
"displayName": "${SERVICE_NAMES[${IDX}]} 90% - Latency - Calendar Day"
}
EOF
    )

    echo POST LATENCY ${SERVICE_NAMES[${IDX}]}
    LATENCY_POST_OUTPUT=$(curl -s -X POST -H "Authorization: Bearer $OAUTH_TOKEN" -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/services/${SERVICE_ID}/serviceLevelObjectives" \
        -d "${LATENCY_SLO_POST}")
    
    # get the slo name/id created to create alert
    SLO_NAME=$(echo ${LATENCY_POST_OUTPUT} | jq -r .name)
    echo SLO_NAME is ${SLO_NAME}

    cat << EOF > alert-latency-${SERVICE_NAMES[${IDX}]}.yaml
combiner: OR
conditions:
- conditionThreshold:
    comparison: COMPARISON_GT
    duration: 0s
    filter: select_slo_burn_rate("${SLO_NAME}","3600s")
    thresholdValue: 10.0
    trigger:
      count: 1
  displayName: Burn rate on ${SERVICE_NAMES[${IDX}]} 90% - Latency - Calendar Day
displayName: Burn rate on ${SERVICE_NAMES[${IDX}]} 90% - Latency - Calendar Day
EOF

    # create alert
    gcloud alpha monitoring policies create --policy-from-file="alert-latency-${SERVICE_NAMES[${IDX}]}.yaml"
    rm alert-latency-${SERVICE_NAMES[${IDX}]}.yaml

    # create an slo for availability
    if [[ ${SERVICE_NAMES[${IDX}]} == "checkoutservice" ]]; then
        AVAILABILITY_SLO_POST=$(cat << EOF
{
  "displayName": "99.9% ${SERVICE_NAMES[${IDX}]} - Availability - Calendar Day",
  "goal": 0.999,
  "calendarPeriod": "DAY",
  "serviceLevelIndicator": {
    "basicSli": {
      "availability": {}
    }
  }
}
EOF
    )

        echo POST AVAILABILITY ${SERVICE_NAMES[${IDX}]}

        AVAILABILITY_POST_OUTPUT=$(curl -s -X POST -H "Authorization: Bearer $OAUTH_TOKEN" -H "Content-Type: application/json" \
            "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/services/${SERVICE_ID}/serviceLevelObjectives" \
            -d "${AVAILABILITY_SLO_POST}")

        # get the slo name/id created to create alert
        SLO_NAME=$(echo ${AVAILABILITY_POST_OUTPUT} | jq -r .name)
        echo SLO_NAME is ${SLO_NAME}

        cat << EOF > alert-availability-${SERVICE_NAMES[${IDX}]}.yaml
combiner: OR
conditions:
- conditionThreshold:
    comparison: COMPARISON_GT
    duration: 0s
    filter: select_slo_burn_rate("${SLO_NAME}","3600s")
    thresholdValue: 1.0
    trigger:
      count: 1
  displayName: Burn rate on 99.9% ${SERVICE_NAMES[${IDX}]} - Availability - Calendar Day
displayName: Burn rate on 99.9% ${SERVICE_NAMES[${IDX}]} - Availability - Calendar Day
EOF
        # create alert
        gcloud alpha monitoring policies create --policy-from-file="alert-availability-${SERVICE_NAMES[${IDX}]}.yaml"
        rm alert-availability-${SERVICE_NAMES[${IDX}]}.yaml
    fi
done
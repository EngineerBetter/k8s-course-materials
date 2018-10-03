#!/bin/bash

: "${PROJECT:?PROJECT env var must be provided}"

set -euxo pipefail

EXTERNAL_NODE_IPS=$(kubectl get nodes -o jsonpath={.items[*].status.addresses[?\(@.type==\"ExternalIP\"\)].address})

kubectl apply -f helm-service-account.yaml
helm init --service-account helm --wait
helm install helm/uaa-opensuse \
  --namespace uaa \
  --values scf-config-values.yaml \
  --name uaa \
  --set kube.external_ips="{${EXTERNAL_NODE_IPS}}" \
  --set services.UAALoadBalancerIP="$(gcloud compute addresses --project ${PROJECT} describe uaa --region europe-west1 --format json | jq -rc .address)" \
  --wait
SECRET=$(kubectl get pods --namespace uaa -o jsonpath='{.items[*].spec.containers[?(.name=="uaa")].env[?(.name=="INTERNAL_CA_CERT")].valueFrom.secretKeyRef.name}')
CA_CERT="$(kubectl get secret $SECRET --namespace uaa -o jsonpath="{.data['internal-ca-cert']}" | base64 --decode -)"
IFS= helm install helm/cf-opensuse \
  --namespace scf \
  --values scf-config-values.yaml \
  --name scf \
  --set kube.external_ips="{${EXTERNAL_NODE_IPS}}" \
  --set secrets.UAA_CA_CERT="${CA_CERT}" \
  --set services.loadbalanced=true \
  --set services.RouterLoadBalancerIP="$(gcloud compute addresses --project ${PROJECT} describe router --region europe-west1 --format json | jq -rc .address)" \
  --set services.SSHLoadBalancerIP="$(gcloud compute addresses --project ${PROJECT} describe ssh --region europe-west1 --format json | jq -rc .address)" \
  --timeout 600 \
  --wait

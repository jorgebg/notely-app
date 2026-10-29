#!/usr/bin/env bash
# After `terraform destroy`: lists anything of the app still left in the demo project.
# The foundation (bootstrap/: state bucket, network "notely", registries) stays: not listed.
# Prints nothing but the header when the project is clean; exits 1 otherwise.
set -uo pipefail
source "$(dirname "$0")/../demo.env"
P="--project=$DEMO_PROJECT"
left=0
check() {  # check <what> <gcloud command...>
  local what="$1"; shift
  local out; out="$("$@" 2>/dev/null)"
  if [[ -n "$out" ]]; then echo "-- $what"; echo "$out"; left=1; fi
}
echo "Resources left in $DEMO_PROJECT:"
check "Cloud Run services"  gcloud run services list $P --format='value(metadata.name,region)'
check "VM instances"        gcloud compute instances list $P --format='value(name,zone)'
check "disks"               gcloud compute disks list $P --format='value(name,zone)'
check "addresses"           gcloud compute addresses list $P --filter='purpose!=SERVERLESS' --format='value(name,region)'
check "networks"            gcloud compute networks list $P --filter='name!=default AND name!=notely' --format='value(name)'
check "firewall rules"      gcloud compute firewall-rules list $P --filter='network!~/default$' --format='value(name)'
check "buckets"             gcloud storage buckets list $P --filter='name!~-tfstate$' --format='value(name)'
check "secrets"             gcloud secrets list $P --format='value(name)'
check "registries"          gcloud artifacts repositories list $P --location=us-central1 --filter='name!~/(notely|dockerhub)$' --format='value(name)'
check "uptime checks"       gcloud monitoring uptime list-configs $P --format='value(displayName)'
check "alert policies"      gcloud alpha monitoring policies list $P --format='value(displayName)'
[[ $left -eq 0 ]] && echo "(nothing)"
exit $left

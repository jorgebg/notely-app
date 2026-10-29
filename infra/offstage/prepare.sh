#!/usr/bin/env bash
# Offstage preparation for the Terraform demo. Run it once before rehearsing, as yourself
# (gcloud auth login + gcloud auth application-default login). Safe to run again.
#
#   bash infra/offstage/prepare.sh [BILLING_ACCOUNT_ID]
#
# Creates (only if missing):
#   - notely-demo-<suffix>   the project the demo deploys into
#   - notely-guard-<suffix>  the spending guard (budget + kill switch, see guard/)
#   - terraform-runner@<demo>  a service account with Owner on the demo project only;
#                              Terraform impersonates it, so nothing reaches other projects
#   - an e-mail notification channel "made by hand" (step 6.2 imports it)
#   - both app images, built locally and tagged for the registry (step 2.3 pushes them)
# and writes infra/demo.env (git-ignored): `source infra/demo.env` before running terraform.
set -euo pipefail

INFRA="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$INFRA/.." && pwd)"
ENV_FILE="$INFRA/demo.env"
REGION="us-central1"
ME="$(gcloud config get-value account 2>/dev/null)"
[[ -n "$ME" ]] || { echo "Sign in first: gcloud auth login" >&2; exit 1; }

# Values that must survive a re-run come from the previous demo.env.
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
SUFFIX="${DEMO_SUFFIX:-$(openssl rand -hex 3)}"
DEMO="notely-demo-$SUFFIX"
GUARD="notely-guard-$SUFFIX"
ALERT_EMAIL="${TF_VAR_alert_email:-$ME}"

BILLING="${1:-${BILLING_ACCOUNT:-}}"
if [[ -z "$BILLING" ]]; then
  mapfile -t accounts < <(gcloud billing accounts list --filter=open=true --format='value(name)')
  [[ ${#accounts[@]} -eq 1 ]] || { echo "Pass the billing account ID as the first argument" >&2; exit 1; }
  BILLING="${accounts[0]#billingAccounts/}"
fi

for p in "$DEMO" "$GUARD"; do
  if ! gcloud projects describe "$p" >/dev/null 2>&1; then
    echo "== creating project $p"
    gcloud projects create "$p" --name="${p%-*}" --quiet
  fi
  gcloud billing projects link "$p" --billing-account="$BILLING" --quiet >/dev/null
done

echo "== demo project: every API the demo uses (step 2.2 adopts them in seconds instead of minutes)"
gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com run.googleapis.com monitoring.googleapis.com \
  artifactregistry.googleapis.com compute.googleapis.com secretmanager.googleapis.com \
  storage.googleapis.com --project "$DEMO"
gcloud auth application-default set-quota-project "$DEMO" --quiet >/dev/null 2>&1 || true
echo "== guard project: APIs its Terraform calls are billed to"
gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com \
  billingbudgets.googleapis.com cloudbilling.googleapis.com --project "$GUARD"

RUNNER="terraform-runner@$DEMO.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$RUNNER" --project "$DEMO" >/dev/null 2>&1; then
  echo "== creating $RUNNER"
  gcloud iam service-accounts create terraform-runner --project "$DEMO" \
    --display-name="Terraform (demo project only)"
fi
gcloud projects add-iam-policy-binding "$DEMO" --member="serviceAccount:$RUNNER" \
  --role=roles/owner --condition=None --quiet >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$RUNNER" --project "$DEMO" \
  --member="user:$ME" --role=roles/iam.serviceAccountTokenCreator --quiet >/dev/null

echo "== hand-made notification channel (imported in step 6.2)"
CHANNEL="$(gcloud beta monitoring channels list --project "$DEMO" \
  --filter='display_name="Notely alerts" AND type="email"' --format='value(name)' 2>/dev/null | head -1)"
if [[ -z "$CHANNEL" ]]; then
  CHANNEL="$(gcloud beta monitoring channels create --project "$DEMO" --type=email \
    --display-name='Notely alerts' --channel-labels="email_address=$ALERT_EMAIL" --format='value(name)')"
fi

echo "== building both images"
REGISTRY="$REGION-docker.pkg.dev/$DEMO/notely"
docker build -q --platform linux/amd64 -t "$REGISTRY/notely-api:demo" "$ROOT/backend"
docker build -q --platform linux/amd64 -t "$REGISTRY/notely-web:demo" "$ROOT/frontend"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet >/dev/null 2>&1

cat > "$ENV_FILE" <<EOF
# Written by infra/offstage/prepare.sh. Git-ignored: it names real projects.
export DEMO_SUFFIX=$SUFFIX
export BILLING_ACCOUNT=$BILLING
export DEMO_PROJECT=$DEMO
export GUARD_PROJECT=$GUARD
export REGISTRY=$REGISTRY
# Terraform runs as terraform-runner (Owner of the demo project, nothing else).
export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=$RUNNER
# Steps 1.x have no variables yet: the provider reads the project from here.
export GOOGLE_CLOUD_PROJECT=$DEMO
# gcloud ignores GOOGLE_CLOUD_PROJECT: its own setting, for the gcloud commands in the notes.
export CLOUDSDK_CORE_PROJECT=$DEMO
export TF_VAR_project_id=$DEMO
export TF_VAR_alert_email=$ALERT_EMAIL
export TF_VAR_notification_channel=$CHANNEL
EOF
echo "== done: source infra/demo.env"

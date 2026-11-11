#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 || "$1" != */* ]]; then
  echo "Usage: ./scripts/configure-github.sh OWNER/REPO (public repo)" >&2; exit 1
fi
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO="$1"
API_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO") || {
 echo "Cannot read repo $REPO. Create it as PUBLIC first, and retry." >&2; exit 1;
}
SUBJECT=$(python3 -c 'import json,sys; j=json.load(sys.stdin); print("repo:%s@%s/%s@%s:ref:refs/heads/main" % (j["owner"]["login"], j["owner"]["id"], j["name"], j["id"]))' <<< "$API_JSON")
python3 - "$ROOT/infra/github.auto.tfvars.json" "$SUBJECT" <<'PY'
import json,sys
with open(sys.argv[1], "w") as f: json.dump({"github_oidc_subject": sys.argv[2]}, f, indent=2)
PY
echo "Configured exact OIDC subject for $REPO on main branch."
echo "Now: cd infra && terraform apply"

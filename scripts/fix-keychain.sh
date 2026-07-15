#!/usr/bin/env bash
#
# One-time repair for a "Claude Code-credentials" Keychain item whose ACL
# got re-scoped (symptom: endless keychain password prompts from
# security / Claude Code / ClaudeLimit).
#
# Run it in Terminal. macOS will prompt ONCE — enter your login keychain
# password and click "Always Allow". The item is then recreated with the
# default ACL and every reader goes silent again.

set -euo pipefail

SERVICE="Claude Code-credentials"

ACCOUNT=$(security find-generic-password -s "$SERVICE" 2>/dev/null \
  | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')
ACCOUNT="${ACCOUNT:-$USER}"

echo "Service: $SERVICE"
echo "Account: $ACCOUNT"
echo
echo ">> A keychain prompt will appear now."
echo ">> Enter your login password and click 'Always Allow' (or 'Allow')."
echo

J=$(security find-generic-password -s "$SERVICE" -w)
[ -n "$J" ] || { echo "Read failed — prompt denied?"; exit 1; }

echo "$J" | python3 -c 'import sys,json; json.load(sys.stdin)' \
  || { echo "Value is not valid JSON — aborting, nothing was changed"; exit 1; }

echo "Read OK — recreating the item with a clean ACL"
security delete-generic-password -s "$SERVICE" >/dev/null
security add-generic-password -s "$SERVICE" -a "$ACCOUNT" -w "$J"
unset J

security find-generic-password -s "$SERVICE" -w >/dev/null \
  && echo "Done — silent read OK. Keychain prompts are gone."

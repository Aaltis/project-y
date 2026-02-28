#!/usr/bin/env bash
# system-test.sh - End-to-end CRM API tests
#
# Usage: ./scripts/system-test.sh [--rate-limit]
#
# Tests:
#   Auth         - login with crm realm, reject unauthenticated requests
#   Accounts     - CRUD + access control (user2 gets 403 on user1's resources)
#   Contacts     - create and list contacts
#   Opportunities - create, valid stage advance, invalid stage advance, access control
#   Activities   - create and list
#
# Prerequisites:
#   Port-forward running: ./scripts/port-forward.ps1 start
#   Two Keycloak users: testuser / testuser2 (created by keycloak-init-job)

set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
REALM="crm"
CLIENT_ID="crm-api"
USER1="${KC_USERNAME:-testuser}"
PASS1="${KC_PASSWORD:-testpassword}"
USER2="${KC_USERNAME2:-testuser2}"
PASS2="${KC_PASSWORD2:-testpassword2}"

RUN_RATE_LIMIT=false
for arg in "$@"; do
    case $arg in --rate-limit) RUN_RATE_LIMIT=true ;; *) echo "Unknown: $arg"; exit 1 ;; esac
done

PASS=0; FAIL=0; SKIP=0

pass() { echo "  [PASS] $*"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $*"; ((FAIL++)) || true; }
skip() { echo "  [SKIP] $*"; ((SKIP++)) || true; }
section() { echo ""; echo "==> $*"; }

# http_status <curl-args...> - returns numeric HTTP status, never exits on error
http_status() { curl -s -o /dev/null -w "%{http_code}" "$@" 2>/dev/null || echo "000"; }

# http_body <curl-args...> - returns response body
http_body() { curl -s "$@" 2>/dev/null || true; }

# json_field <field> <json> - extracts field value from JSON string
json_field() {
    local field="$1" json="$2"
    echo "$json" | grep -o "\"${field}\":\"[^\"]*\"" | head -1 | cut -d'"' -f4 || \
    echo "$json" | grep -o "\"${field}\":[^,}]*"     | head -1 | cut -d':' -f2 | tr -d ' "' || \
    true
}

get_token() {
    local user="$1" pass="$2"
    local resp
    resp=$(http_body -X POST "$BASE_URL/auth/realms/$REALM/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password&client_id=$CLIENT_ID&username=$user&password=$pass")
    json_field "access_token" "$resp"
}

# ============================================================================
# PREREQ
# ============================================================================
section "Prereq: Keycloak crm realm at $BASE_URL"

STATUS=$(http_status "$BASE_URL/auth/realms/$REALM")
if [ "$STATUS" = "200" ]; then
    pass "crm realm reachable"
else
    echo "  [ERROR] Cannot reach $BASE_URL/auth/realms/$REALM (HTTP $STATUS)"
    echo "          Run: ./scripts/port-forward.ps1 start"
    exit 1
fi

# ============================================================================
# AUTH
# ============================================================================
section "T01: Login as $USER1 (crm_sales)"
TOKEN1=$(get_token "$USER1" "$PASS1")
if [ -n "$TOKEN1" ]; then pass "Login as '$USER1' OK"; else fail "Login as '$USER1' failed"; exit 1; fi

section "T02: Login as $USER2 (crm_sales)"
TOKEN2=$(get_token "$USER2" "$PASS2")
if [ -n "$TOKEN2" ]; then
    pass "Login as '$USER2' OK"
else
    fail "Login as '$USER2' failed (run reinstall to re-run keycloak-init-job)"
fi

section "T03: No token -> GET /api/accounts returns 401"
STATUS=$(http_status "$BASE_URL/api/accounts")
if [ "$STATUS" = "401" ]; then
    pass "GET /api/accounts (no token) -> 401"
else
    fail "Expected 401, got $STATUS  [Accounts service deployed?]"
fi

# ============================================================================
# ACCOUNTS - happy path
# ============================================================================
section "T04: $USER1 creates account -> 200 with id"
ACCOUNT_ID1=""
RESP=$(http_body -X POST "$BASE_URL/api/accounts" \
    -H "Authorization: Bearer $TOKEN1" \
    -H "Content-Type: application/json" \
    -d '{"name":"Acme Corp"}')
ACCOUNT_ID1=$(json_field "id" "$RESP")
if [ -n "$ACCOUNT_ID1" ]; then pass "Account created id=$ACCOUNT_ID1"; else fail "No id in response: $RESP"; fi

section "T05: $USER1 lists accounts -> includes own"
RESP=$(http_body "$BASE_URL/api/accounts" -H "Authorization: Bearer $TOKEN1")
TOTAL=$(json_field "totalElements" "$RESP")
if [ -n "$TOTAL" ] && [ "$TOTAL" -gt 0 ] 2>/dev/null; then
    pass "GET /api/accounts -> $TOTAL account(s)"
else
    fail "Expected >=1 account, totalElements='$TOTAL'"
fi

section "T06: $USER1 reads own account -> 200"
if [ -n "$ACCOUNT_ID1" ]; then
    STATUS=$(http_status "$BASE_URL/api/accounts/$ACCOUNT_ID1" -H "Authorization: Bearer $TOKEN1")
    if [ "$STATUS" = "200" ]; then pass "GET /api/accounts/$ACCOUNT_ID1 -> 200"; else fail "Expected 200, got $STATUS"; fi
else skip "No account from T04"; fi

section "T07: $USER1 updates own account -> 200"
if [ -n "$ACCOUNT_ID1" ]; then
    STATUS=$(http_status -X PUT "$BASE_URL/api/accounts/$ACCOUNT_ID1" \
        -H "Authorization: Bearer $TOKEN1" \
        -H "Content-Type: application/json" \
        -d '{"name":"Acme Corp (Updated)"}')
    if [ "$STATUS" = "200" ]; then pass "PUT /api/accounts/$ACCOUNT_ID1 -> 200"; else fail "Expected 200, got $STATUS"; fi
else skip "No account from T04"; fi

# ============================================================================
# ACCESS CONTROL - user2 must be blocked from user1's resources
# ============================================================================
section "T08: $USER2 reads $USER1's account -> 403"
if [ -n "$ACCOUNT_ID1" ] && [ -n "$TOKEN2" ]; then
    STATUS=$(http_status "$BASE_URL/api/accounts/$ACCOUNT_ID1" -H "Authorization: Bearer $TOKEN2")
    if [ "$STATUS" = "403" ]; then pass "GET /api/accounts/$ACCOUNT_ID1 as $USER2 -> 403"; else fail "Expected 403, got $STATUS"; fi
else skip "Missing account id or user2 token"; fi

section "T09: $USER2 updates $USER1's account -> 403"
if [ -n "$ACCOUNT_ID1" ] && [ -n "$TOKEN2" ]; then
    STATUS=$(http_status -X PUT "$BASE_URL/api/accounts/$ACCOUNT_ID1" \
        -H "Authorization: Bearer $TOKEN2" \
        -H "Content-Type: application/json" \
        -d '{"name":"Hacked!"}')
    if [ "$STATUS" = "403" ]; then pass "PUT /api/accounts/$ACCOUNT_ID1 as $USER2 -> 403"; else fail "Expected 403, got $STATUS"; fi
else skip "Missing account id or user2 token"; fi

section "T10: $USER2 deletes $USER1's account -> 403"
if [ -n "$ACCOUNT_ID1" ] && [ -n "$TOKEN2" ]; then
    STATUS=$(http_status -X DELETE "$BASE_URL/api/accounts/$ACCOUNT_ID1" -H "Authorization: Bearer $TOKEN2")
    if [ "$STATUS" = "403" ]; then pass "DELETE /api/accounts/$ACCOUNT_ID1 as $USER2 -> 403"; else fail "Expected 403, got $STATUS"; fi
else skip "Missing account id or user2 token"; fi

section "T11: $USER2 account list does NOT expose $USER1's account"
if [ -n "$ACCOUNT_ID1" ] && [ -n "$TOKEN2" ]; then
    RESP=$(http_body "$BASE_URL/api/accounts" -H "Authorization: Bearer $TOKEN2")
    if echo "$RESP" | grep -q "$ACCOUNT_ID1"; then
        fail "$USER2 can see $USER1's account in list response"
    else
        pass "$USER2's list does not expose $USER1's account"
    fi
else skip "Missing account id or user2 token"; fi

section "T12: $USER2 creates own account -> 200"
ACCOUNT_ID2=""
if [ -n "$TOKEN2" ]; then
    RESP=$(http_body -X POST "$BASE_URL/api/accounts" \
        -H "Authorization: Bearer $TOKEN2" \
        -H "Content-Type: application/json" \
        -d '{"name":"Beta LLC"}')
    ACCOUNT_ID2=$(json_field "id" "$RESP")
    if [ -n "$ACCOUNT_ID2" ]; then pass "Account created id=$ACCOUNT_ID2"; else fail "No id in response: $RESP"; fi
else skip "No user2 token"; fi

# ============================================================================
# CONTACTS
# ============================================================================
section "T13: Create contact for $USER1's account -> 200"
CONTACT_ID=""
if [ -n "$ACCOUNT_ID1" ]; then
    RESP=$(http_body -X POST "$BASE_URL/api/contacts" \
        -H "Authorization: Bearer $TOKEN1" \
        -H "Content-Type: application/json" \
        -d "{\"accountId\":\"$ACCOUNT_ID1\",\"name\":\"Jane Doe\",\"email\":\"jane@acme.com\",\"phone\":\"555-0100\"}")
    CONTACT_ID=$(json_field "id" "$RESP")
    if [ -n "$CONTACT_ID" ]; then pass "Contact created id=$CONTACT_ID"; else fail "No id in response: $RESP"; fi
else skip "No account from T04"; fi

section "T14: List contacts for account -> includes created contact"
if [ -n "$ACCOUNT_ID1" ]; then
    RESP=$(http_body "$BASE_URL/api/contacts?accountId=$ACCOUNT_ID1" -H "Authorization: Bearer $TOKEN1")
    if echo "$RESP" | grep -q '"id"'; then
        pass "GET /api/contacts?accountId=$ACCOUNT_ID1 -> has contacts"
    else
        fail "Expected contacts list with entries, got: $RESP"
    fi
else skip "No account from T04"; fi

# ============================================================================
# OPPORTUNITIES
# ============================================================================
section "T15: Create opportunity for $USER1 -> 200 stage=PROSPECT"
OPP_ID=""
if [ -n "$ACCOUNT_ID1" ]; then
    RESP=$(http_body -X POST "$BASE_URL/api/opportunities" \
        -H "Authorization: Bearer $TOKEN1" \
        -H "Content-Type: application/json" \
        -d "{\"accountId\":\"$ACCOUNT_ID1\",\"name\":\"Big Deal\",\"amount\":50000}")
    OPP_ID=$(json_field "id" "$RESP")
    STAGE=$(json_field "stage" "$RESP")
    if [ -n "$OPP_ID" ]; then pass "Opportunity created id=$OPP_ID stage=$STAGE"; else fail "No id in response: $RESP"; fi
else skip "No account from T04"; fi

section "T16: Advance stage PROSPECT -> QUALIFY -> 200"
if [ -n "$OPP_ID" ]; then
    STATUS=$(http_status -X PATCH "$BASE_URL/api/opportunities/$OPP_ID/stage" \
        -H "Authorization: Bearer $TOKEN1" \
        -H "Content-Type: application/json" \
        -d '{"stage":"QUALIFY"}')
    if [ "$STATUS" = "200" ]; then pass "Stage PROSPECT->QUALIFY -> 200"; else fail "Expected 200, got $STATUS"; fi
else skip "No opportunity from T15"; fi

section "T17: Invalid transition QUALIFY -> WON -> 400"
if [ -n "$OPP_ID" ]; then
    STATUS=$(http_status -X PATCH "$BASE_URL/api/opportunities/$OPP_ID/stage" \
        -H "Authorization: Bearer $TOKEN1" \
        -H "Content-Type: application/json" \
        -d '{"stage":"WON"}')
    if [ "$STATUS" = "400" ]; then pass "Stage QUALIFY->WON -> 400 (blocked)"; else fail "Expected 400, got $STATUS"; fi
else skip "No opportunity from T15"; fi

section "T18: $USER2 cannot read $USER1's opportunity -> 403"
if [ -n "$OPP_ID" ] && [ -n "$TOKEN2" ]; then
    STATUS=$(http_status "$BASE_URL/api/opportunities/$OPP_ID" -H "Authorization: Bearer $TOKEN2")
    if [ "$STATUS" = "403" ]; then pass "GET /api/opportunities/$OPP_ID as $USER2 -> 403"; else fail "Expected 403, got $STATUS"; fi
else skip "Missing opportunity id or user2 token"; fi

# ============================================================================
# ACTIVITIES
# ============================================================================
section "T19: Create activity for opportunity -> 200"
ACTIVITY_ID=""
if [ -n "$OPP_ID" ]; then
    RESP=$(http_body -X POST "$BASE_URL/api/activities" \
        -H "Authorization: Bearer $TOKEN1" \
        -H "Content-Type: application/json" \
        -d "{\"opportunityId\":\"$OPP_ID\",\"type\":\"NOTE\",\"text\":\"Initial contact made\"}")
    ACTIVITY_ID=$(json_field "id" "$RESP")
    if [ -n "$ACTIVITY_ID" ]; then pass "Activity created id=$ACTIVITY_ID"; else fail "No id in response: $RESP"; fi
else skip "No opportunity from T15"; fi

section "T20: List activities for opportunity -> includes created activity"
if [ -n "$OPP_ID" ]; then
    RESP=$(http_body "$BASE_URL/api/activities?opportunityId=$OPP_ID" -H "Authorization: Bearer $TOKEN1")
    if echo "$RESP" | grep -q '"id"'; then
        pass "GET /api/activities?opportunityId=$OPP_ID -> has activities"
    else
        fail "Expected activities list with entries, got: $RESP"
    fi
else skip "No opportunity from T15"; fi

# ============================================================================
# CLEANUP
# ============================================================================
section "T21: $USER1 deletes own account -> 204"
if [ -n "$ACCOUNT_ID1" ]; then
    STATUS=$(http_status -X DELETE "$BASE_URL/api/accounts/$ACCOUNT_ID1" -H "Authorization: Bearer $TOKEN1")
    if [ "$STATUS" = "204" ]; then pass "DELETE /api/accounts/$ACCOUNT_ID1 -> 204"; else fail "Expected 204, got $STATUS"; fi
else skip "No account from T04"; fi

# ============================================================================
# RATE LIMITING (optional)
# ============================================================================
if [ "$RUN_RATE_LIMIT" = true ]; then
    section "T22: Rate limiting -> expect HTTP 429 after burst"
    GOT_429=false
    for i in $(seq 1 10); do
        STATUS=$(http_status -X POST "$BASE_URL/api/accounts" \
            -H "Authorization: Bearer $TOKEN1" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"Burst$i\"}")
        if [ "$STATUS" = "429" ]; then GOT_429=true; break; fi
    done
    if [ "$GOT_429" = true ]; then pass "HTTP 429 received (rate limit active)"; else fail "No HTTP 429 within 10 requests"; fi
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "================================="
SKIP_NOTE=""
if [ "$SKIP" -gt 0 ]; then SKIP_NOTE=", $SKIP skipped"; fi
echo "Results: $PASS passed, $FAIL failed$SKIP_NOTE"
echo "================================="
[ "$FAIL" -eq 0 ]

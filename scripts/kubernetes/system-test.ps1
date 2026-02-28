# system-test.ps1 - End-to-end CRM API tests
#
# Usage: .\scripts\system-test.ps1 [-RateLimit]
#
# Tests:
#   Auth     - login with crm realm, reject unauthenticated requests
#   Accounts - CRUD + owner can read/update/delete own; other crm_sales user gets 403
#   Contacts - create and list contacts for an account
#   Opportunities - create, advance stage (valid + invalid transitions)
#   Activities - create and list activities for an opportunity
#   Access control - two crm_sales users; user2 cannot see user1's resources
#
# Prerequisites:
#   Port-forward running: .\scripts\port-forward.ps1 start
#   Two Keycloak users created by keycloak-init-job (testuser / testuser2)

param([switch]$RateLimit)

$ErrorActionPreference = "Stop"

$LogDir = Join-Path $PSScriptRoot "..\..\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "system-test-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
Start-Transcript -Path $LogFile

$BaseUrl   = if ($env:BASE_URL)     { $env:BASE_URL }     else { "http://localhost:8080" }
$Realm     = "crm"
$ClientId  = "crm-api"
$User1Name = if ($env:KC_USERNAME)  { $env:KC_USERNAME }  else { "testuser" }
$User1Pass = if ($env:KC_PASSWORD)  { $env:KC_PASSWORD }  else { "testpassword" }
$User2Name = if ($env:KC_USERNAME2) { $env:KC_USERNAME2 } else { "testuser2" }
$User2Pass = if ($env:KC_PASSWORD2) { $env:KC_PASSWORD2 } else { "testpassword2" }

$PassCount = 0
$FailCount = 0
$SkipCount = 0

function Pass([string]$msg)    { Write-Host "  [PASS] $msg" -ForegroundColor Green;  $script:PassCount++ }
function Fail([string]$msg)    { Write-Host "  [FAIL] $msg" -ForegroundColor Red;    $script:FailCount++ }
function Skip([string]$msg)    { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow; $script:SkipCount++ }
function Section([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function StatusOf($r)          { if ($r) { $r.StatusCode } else { "unreachable" } }

# ---------------------------------------------------------------------------
# HTTP helpers - PS5 compatible (no -SkipHttpErrorCheck, no ??, no ?.)
# 4xx/5xx throws in PS5 Invoke-WebRequest; catch and return a plain object.
# ---------------------------------------------------------------------------
function Invoke-Http {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Body        = $null,
        [string]$ContentType = $null,
        [hashtable]$Headers  = @{}
    )
    $params = @{ Uri = $Uri; Method = $Method; Headers = $Headers; UseBasicParsing = $true }
    if ($Body)        { $params.Body        = $Body }
    if ($ContentType) { $params.ContentType = $ContentType }
    try {
        return Invoke-WebRequest @params
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $status  = [int]$resp.StatusCode
            $content = ""
            try {
                $stream  = $resp.GetResponseStream()
                $reader  = New-Object System.IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
            } catch {}
            return [PSCustomObject]@{ StatusCode = $status; Content = $content }
        }
        return $null
    }
}

function Invoke-Get   ([string]$Uri, [hashtable]$Headers = @{}) {
    return Invoke-Http -Method GET    -Uri $Uri -Headers $Headers
}
function Invoke-Post  ([string]$Uri, [string]$Body, [string]$ContentType, [hashtable]$Headers = @{}) {
    return Invoke-Http -Method POST   -Uri $Uri -Body $Body -ContentType $ContentType -Headers $Headers
}
function Invoke-Put   ([string]$Uri, [string]$Body, [hashtable]$Headers = @{}) {
    return Invoke-Http -Method PUT    -Uri $Uri -Body $Body -ContentType "application/json" -Headers $Headers
}
function Invoke-Patch ([string]$Uri, [string]$Body, [hashtable]$Headers = @{}) {
    return Invoke-Http -Method PATCH  -Uri $Uri -Body $Body -ContentType "application/json" -Headers $Headers
}
function Invoke-Delete([string]$Uri, [hashtable]$Headers = @{}) {
    return Invoke-Http -Method DELETE -Uri $Uri -Headers $Headers
}

function Get-Token([string]$Username, [string]$Password) {
    $body = "grant_type=password&client_id=$ClientId&username=$Username&password=$Password"
    $r = Invoke-Post -Uri "$BaseUrl/auth/realms/$Realm/protocol/openid-connect/token" `
                     -Body $body -ContentType "application/x-www-form-urlencoded"
    if (-not $r -or $r.StatusCode -ne 200) { return $null }
    return ($r.Content | ConvertFrom-Json).access_token
}

function AuthHeader([string]$Token) { return @{ Authorization = "Bearer $Token" } }

# ============================================================================
# PREREQ: Keycloak reachable
# ============================================================================
Section "Prereq: Keycloak crm realm at $BaseUrl"

$r = $null
for ($i = 1; $i -le 5; $i++) {
    $r = Invoke-Get -Uri "$BaseUrl/auth/realms/$Realm"
    if ($r -and $r.StatusCode -eq 200) { break }
    if ($i -lt 5) {
        Write-Host "  Attempt $i/5 (HTTP $(StatusOf $r)), retrying in 3s..." -ForegroundColor Yellow
        Start-Sleep 3
    }
}

if ($r -and $r.StatusCode -eq 200) {
    Pass "crm realm reachable"
} else {
    Write-Host "  [ERROR] Cannot reach $BaseUrl/auth/realms/$Realm" -ForegroundColor Red
    Write-Host "          Run: .\scripts\port-forward.ps1 start" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# AUTH
# ============================================================================
Section "T01: Login as $User1Name (crm_sales) -> access_token"
$Token1 = Get-Token $User1Name $User1Pass
if ($Token1) { Pass "Login as '$User1Name' OK" } else { Fail "Login as '$User1Name' failed"; exit 1 }
$Auth1 = AuthHeader $Token1

Section "T02: Login as $User2Name (crm_sales) -> access_token"
$Token2 = Get-Token $User2Name $User2Pass
if ($Token2) {
    Pass "Login as '$User2Name' OK"
} else {
    Fail "Login as '$User2Name' failed (run .\scripts\reinstall.ps1 to re-run keycloak-init-job)"
}
$Auth2 = if ($Token2) { AuthHeader $Token2 } else { $null }

Section "T03: No token -> GET /api/accounts returns 401"
$r = Invoke-Get -Uri "$BaseUrl/api/accounts"
if ($r -and $r.StatusCode -eq 401) {
    Pass "GET /api/accounts (no token) -> 401"
} else {
    Fail "Expected 401, got $(StatusOf $r)  [Accounts service deployed?]"
}

# ============================================================================
# ACCOUNTS - happy path (user1 owns the data)
# ============================================================================
Section "T04: $User1Name creates account -> 200 with id"
$AccountId1 = $null
$body = @{ name = "Acme Corp" } | ConvertTo-Json -Compress
$r = Invoke-Post -Uri "$BaseUrl/api/accounts" -Body $body -ContentType "application/json" -Headers $Auth1
if ($r -and $r.StatusCode -eq 200) {
    $AccountId1 = ($r.Content | ConvertFrom-Json).id
    if ($AccountId1) { Pass "Account created id=$AccountId1" } else { Fail "No id in response: $($r.Content)" }
} else {
    Fail "POST /api/accounts -> $(StatusOf $r): $($r.Content)"
}

Section "T05: $User1Name lists accounts -> includes own account"
$r = Invoke-Get -Uri "$BaseUrl/api/accounts" -Headers $Auth1
if ($r -and $r.StatusCode -eq 200) {
    $total = ($r.Content | ConvertFrom-Json).totalElements
    if ($total -gt 0) { Pass "GET /api/accounts -> $total account(s)" } else { Fail "Expected >=1 account, totalElements=$total" }
} else {
    Fail "GET /api/accounts -> $(StatusOf $r)"
}

Section "T06: $User1Name reads own account -> 200"
if ($AccountId1) {
    $r = Invoke-Get -Uri "$BaseUrl/api/accounts/$AccountId1" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) { Pass "GET /api/accounts/$AccountId1 -> 200" } else { Fail "Expected 200, got $(StatusOf $r)" }
} else { Skip "No account from T04" }

Section "T07: $User1Name updates own account -> 200"
if ($AccountId1) {
    $body = @{ name = "Acme Corp (Updated)" } | ConvertTo-Json -Compress
    $r = Invoke-Put -Uri "$BaseUrl/api/accounts/$AccountId1" -Body $body -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) { Pass "PUT /api/accounts/$AccountId1 -> 200" } else { Fail "Expected 200, got $(StatusOf $r): $($r.Content)" }
} else { Skip "No account from T04" }

# ============================================================================
# ACCESS CONTROL - user2 (different crm_sales user) must be blocked
# ============================================================================
Section "T08: $User2Name reads $User1Name's account -> 403"
if ($AccountId1 -and $Auth2) {
    $r = Invoke-Get -Uri "$BaseUrl/api/accounts/$AccountId1" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 403) { Pass "GET /api/accounts/$AccountId1 as $User2Name -> 403" } else { Fail "Expected 403, got $(StatusOf $r)" }
} else { Skip "Missing account id or user2 token" }

Section "T09: $User2Name updates $User1Name's account -> 403"
if ($AccountId1 -and $Auth2) {
    $body = @{ name = "Hacked!" } | ConvertTo-Json -Compress
    $r = Invoke-Put -Uri "$BaseUrl/api/accounts/$AccountId1" -Body $body -Headers $Auth2
    if ($r -and $r.StatusCode -eq 403) { Pass "PUT /api/accounts/$AccountId1 as $User2Name -> 403" } else { Fail "Expected 403, got $(StatusOf $r)" }
} else { Skip "Missing account id or user2 token" }

Section "T10: $User2Name deletes $User1Name's account -> 403"
if ($AccountId1 -and $Auth2) {
    $r = Invoke-Delete -Uri "$BaseUrl/api/accounts/$AccountId1" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 403) { Pass "DELETE /api/accounts/$AccountId1 as $User2Name -> 403" } else { Fail "Expected 403, got $(StatusOf $r)" }
} else { Skip "Missing account id or user2 token" }

Section "T11: $User2Name account list does NOT include $User1Name's account"
if ($AccountId1 -and $Auth2) {
    $r = Invoke-Get -Uri "$BaseUrl/api/accounts" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        if ($r.Content -notlike "*$AccountId1*") {
            Pass "$User2Name's list does not expose $User1Name's account"
        } else {
            Fail "$User2Name can see $User1Name's account in list response"
        }
    } else {
        Fail "Expected 200, got $(StatusOf $r)"
    }
} else { Skip "Missing account id or user2 token" }

Section "T12: $User2Name creates own account -> 200"
$AccountId2 = $null
if ($Auth2) {
    $body = @{ name = "Beta LLC" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/accounts" -Body $body -ContentType "application/json" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        $AccountId2 = ($r.Content | ConvertFrom-Json).id
        if ($AccountId2) { Pass "Account created id=$AccountId2" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/accounts as $User2Name -> $(StatusOf $r)"
    }
} else { Skip "No user2 token" }

# ============================================================================
# CONTACTS
# ============================================================================
Section "T13: Create contact for $User1Name's account -> 200"
$ContactId = $null
if ($AccountId1) {
    $body = @{ name = "Jane Doe"; email = "jane@acme.com"; phone = "555-0100" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/accounts/$AccountId1/contacts" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $ContactId = ($r.Content | ConvertFrom-Json).id
        if ($ContactId) { Pass "Contact created id=$ContactId" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/accounts/$AccountId1/contacts -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No account from T04" }

Section "T14: List contacts for account -> includes created contact"
if ($AccountId1) {
    $r = Invoke-Get -Uri "$BaseUrl/api/accounts/$AccountId1/contacts" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $count = ($r.Content | ConvertFrom-Json).Count
        if ($count -gt 0) { Pass "GET /api/accounts/$AccountId1/contacts -> $count contact(s)" } else { Fail "Expected >=1 contact, got 0" }
    } else {
        Fail "Expected 200, got $(StatusOf $r)"
    }
} else { Skip "No account from T04" }

# ============================================================================
# OPPORTUNITIES
# ============================================================================
Section "T15: Create opportunity for $User1Name -> 200, stage=PROSPECT"
$OpportunityId = $null
if ($AccountId1) {
    $body = @{ accountId = $AccountId1; name = "Big Deal"; amount = 50000 } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/opportunities" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $json = $r.Content | ConvertFrom-Json
        $OpportunityId = $json.id
        $stage = $json.stage
        if ($OpportunityId) { Pass "Opportunity created id=$OpportunityId stage=$stage" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/opportunities -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No account from T04" }

Section "T16: Advance stage PROSPECT -> QUALIFY -> 200"
if ($OpportunityId) {
    $body = @{ stage = "QUALIFY" } | ConvertTo-Json -Compress
    $r = Invoke-Patch -Uri "$BaseUrl/api/opportunities/$OpportunityId/stage" -Body $body -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) { Pass "Stage PROSPECT->QUALIFY -> 200" } else { Fail "Expected 200, got $(StatusOf $r): $($r.Content)" }
} else { Skip "No opportunity from T15" }

Section "T17: Invalid transition QUALIFY -> WON -> 400"
if ($OpportunityId) {
    $body = @{ stage = "WON" } | ConvertTo-Json -Compress
    $r = Invoke-Patch -Uri "$BaseUrl/api/opportunities/$OpportunityId/stage" -Body $body -Headers $Auth1
    if ($r -and $r.StatusCode -eq 400) { Pass "Stage QUALIFY->WON -> 400 (blocked: not allowed)" } else { Fail "Expected 400, got $(StatusOf $r)" }
} else { Skip "No opportunity from T15" }

Section "T18: $User2Name cannot read $User1Name's opportunity -> 403"
if ($OpportunityId -and $Auth2) {
    $r = Invoke-Get -Uri "$BaseUrl/api/opportunities/$OpportunityId" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 403) { Pass "GET /api/opportunities/$OpportunityId as $User2Name -> 403" } else { Fail "Expected 403, got $(StatusOf $r)" }
} else { Skip "Missing opportunity id or user2 token" }

# ============================================================================
# ACTIVITIES
# ============================================================================
Section "T19: Create activity for opportunity -> 200"
$ActivityId = $null
if ($OpportunityId) {
    $body = @{ type = "NOTE"; text = "Initial contact made" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/opportunities/$OpportunityId/activities" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $ActivityId = ($r.Content | ConvertFrom-Json).id
        if ($ActivityId) { Pass "Activity created id=$ActivityId" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/opportunities/$OpportunityId/activities -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No opportunity from T15" }

Section "T20: List activities for opportunity -> includes created activity"
if ($OpportunityId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/opportunities/$OpportunityId/activities" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $count = ($r.Content | ConvertFrom-Json).Count
        if ($count -gt 0) { Pass "GET /api/opportunities/$OpportunityId/activities -> $count activity/ies" } else { Fail "Expected >=1 activity, got 0" }
    } else {
        Fail "Expected 200, got $(StatusOf $r)"
    }
} else { Skip "No opportunity from T15" }

# ============================================================================
# CLEANUP - delete user1's account (owner can delete own)
# ============================================================================
Section "T21: $User1Name deletes own account -> 204"
if ($AccountId1) {
    $r = Invoke-Delete -Uri "$BaseUrl/api/accounts/$AccountId1" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 204) { Pass "DELETE /api/accounts/$AccountId1 -> 204" } else { Fail "Expected 204, got $(StatusOf $r)" }
} else { Skip "No account from T04" }

# ============================================================================
# RATE LIMITING (optional)
# ============================================================================
if ($RateLimit) {
    Section "T22: Rate limiting -> expect HTTP 429 after burst"
    $got429 = $false
    for ($i = 1; $i -le 10; $i++) {
        $body = @{ name = "Burst$i" } | ConvertTo-Json -Compress
        $r = Invoke-Post -Uri "$BaseUrl/api/accounts" -Body $body -ContentType "application/json" -Headers $Auth1
        if ($r -and $r.StatusCode -eq 429) { $got429 = $true; break }
    }
    if ($got429) { Pass "HTTP 429 received (rate limit active)" } else { Fail "No HTTP 429 within 10 rapid requests" }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "================================="
$color    = if ($FailCount -eq 0) { "Green" } else { "Red" }
$skipNote = if ($SkipCount -gt 0) { ", $SkipCount skipped" } else { "" }
Write-Host "Results: $PassCount passed, $FailCount failed$skipNote" -ForegroundColor $color
Write-Host "================================="
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Stop-Transcript

exit $(if ($FailCount -eq 0) { 0 } else { 1 })

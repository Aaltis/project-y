# system-test.ps1 - End-to-end CRM + PMBOK API tests for Docker Compose stack
#
# Usage:
#   .\scripts\docker\system-test.ps1             # run all tests
#   .\scripts\docker\system-test.ps1 -RateLimit  # also test HTTP 429 rate limiting
#   .\scripts\docker\system-test.ps1 -SkipCRM    # run only PMBOK tests
#   .\scripts\docker\system-test.ps1 -SkipPMBOK  # run only CRM tests
#
# Tests:
#   T01-T22   CRM core (auth, accounts, contacts, opportunities, activities, log consumer)
#   P01-P40   PMBOK Projects module (all phases: identity, initiation, planning,
#             execution, monitoring & controlling, closing)
#   P01a,P01b  GET /api/projects list (caller sees own projects; SPONSOR sees shared)
#
# Prerequisites:
#   Stack running: .\scripts\docker\compose-up.ps1
#   (keycloak-init creates testuser / testuser2 automatically on first start)

param(
    [switch]$RateLimit,
    [switch]$SkipCRM,
    [switch]$SkipPMBOK
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$LogDir = Join-Path $ProjectRoot "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "system-test-docker-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
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
# HTTP helpers - PS5 compatible (no -SkipHttpErrorCheck; 4xx/5xx throws)
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

# Decode JWT payload (Base64Url) and extract the 'sub' claim (Keycloak user UUID)
function Get-Sub([string]$Token) {
    $payload = $Token.Split('.')[1]
    $payload = $payload.Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '='  }
    }
    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
    return ($decoded | ConvertFrom-Json).sub
}

# ============================================================================
# PREREQ: stack reachable
# ============================================================================
Section "Prereq: Docker Compose stack reachable at $BaseUrl"

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
    Write-Host "          Start the stack: .\scripts\docker\compose-up.ps1" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# AUTH (shared by CRM and PMBOK tests)
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
    Fail "Login as '$User2Name' failed (restart stack to re-run keycloak-init)"
}
$Auth2 = if ($Token2) { AuthHeader $Token2 } else { $null }

Section "T03: No token -> GET /api/accounts returns 401"
$r = Invoke-Get -Uri "$BaseUrl/api/accounts"
if ($r -and $r.StatusCode -eq 401) {
    Pass "GET /api/accounts (no token) -> 401"
} else {
    Fail "Expected 401, got $(StatusOf $r)"
}

# ============================================================================
# CRM TESTS (T04-T22)
# ============================================================================
if ($SkipCRM) {
    Write-Host "`n==> CRM tests skipped (-SkipCRM)" -ForegroundColor Yellow
    $AccountId1 = $null; $AccountId2 = $null
} else {

# ============================================================================
# ACCOUNTS
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
    if ($total -gt 0) { Pass "GET /api/accounts -> $total account(s)" } else { Fail "Expected >=1, totalElements=$total" }
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
# ACCESS CONTROL
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
            Fail "$User2Name can see $User1Name's account in list"
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
        $count = @($r.Content | ConvertFrom-Json).Count
        if ($count -gt 0) { Pass "GET /api/accounts/$AccountId1/contacts -> $count contact(s)" } else { Fail "Expected >=1 contact, got 0" }
    } else {
        Fail "Expected 200, got $(StatusOf $r)"
    }
} else { Skip "No account from T04" }

# ============================================================================
# OPPORTUNITIES
# ============================================================================
# Rate-limit pause: refill token bucket before rapid PATCH requests
Start-Sleep -Seconds 2
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
    if ($r -and $r.StatusCode -eq 400) { Pass "Stage QUALIFY->WON -> 400 (blocked)" } else { Fail "Expected 400, got $(StatusOf $r)" }
} else { Skip "No opportunity from T15" }

Section "T18: $User2Name cannot read $User1Name's opportunity -> 403"
if ($OpportunityId -and $Auth2) {
    $r = Invoke-Get -Uri "$BaseUrl/api/opportunities/$OpportunityId" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 403) { Pass "GET /api/opportunities/$OpportunityId as $User2Name -> 403" } else { Fail "Expected 403, got $(StatusOf $r)" }
} else { Skip "Missing opportunity id or user2 token" }

# ============================================================================
# ACTIVITIES
# Gateway rate-limits at 5 req/sec per user; pause to refill the token bucket.
# ============================================================================
Start-Sleep -Seconds 2
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
        $count = @($r.Content | ConvertFrom-Json).Count
        if ($count -gt 0) { Pass "GET /api/opportunities/$OpportunityId/activities -> $count activity/ies" } else { Fail "Expected >=1 activity, got 0" }
    } else {
        Fail "Expected 200, got $(StatusOf $r)"
    }
} else { Skip "No opportunity from T15" }

# ============================================================================
# CLEANUP
# ============================================================================
Start-Sleep -Seconds 1
Section "T21: $User1Name deletes own account -> 204"
if ($AccountId1) {
    $r = Invoke-Delete -Uri "$BaseUrl/api/accounts/$AccountId1" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 204) { Pass "DELETE /api/accounts/$AccountId1 -> 204" } else { Fail "Expected 204, got $(StatusOf $r)" }
} else { Skip "No account from T04" }

# ============================================================================
# LOG CONSUMER - Docker-specific: verify RabbitMQ logs reached logsdb
# ============================================================================
Section "T22: Log Consumer - request_log rows exist in logsdb"
Start-Sleep -Seconds 3   # give RabbitMQ a moment to flush
Push-Location $ProjectRoot
try {
    $result = & docker compose exec -T postgres-logs `
        psql -U loguser -d logsdb -t -c "SELECT COUNT(*) FROM request_log;" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $count = ($result | Where-Object { $_ -match '\d+' } | Select-Object -First 1).Trim()
        if ([int]$count -gt 0) {
            Pass "request_log has $count row(s) - log-consumer is working"
        } else {
            Fail "request_log is empty - log-consumer may not be connected to RabbitMQ"
        }
    } else {
        Fail "Could not query logsdb: $result"
    }
} finally { Pop-Location }

} # end -not $SkipCRM

# ============================================================================
# PMBOK PROJECT MANAGEMENT MODULE  (P01-P32)
# User1 = PM (creates project, manages planning/execution/monitoring)
# User2 = SPONSOR (approves charter, baselines, accepts deliverables)
# ============================================================================
if ($SkipPMBOK) {
    Write-Host "`n==> PMBOK tests skipped (-SkipPMBOK)" -ForegroundColor Yellow
} else {

if (-not $Token2) {
    Write-Host "`n  [WARN] No user2 token - SPONSOR-gated tests will be skipped" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# PREREQ: extract Keycloak sub UUIDs from JWT (needed for sponsorId / assigneeId)
# -----------------------------------------------------------------------
Section "PMBOK Prereq: decode sub UUIDs from JWT"
$Sub1 = $null; $Sub2 = $null
if ($Token1) { $Sub1 = Get-Sub $Token1; Pass "$User1Name sub=$Sub1" }
else         { Fail "No Token1 - cannot run PMBOK tests" }
if ($Token2) { $Sub2 = Get-Sub $Token2; Pass "$User2Name sub=$Sub2" }
else         { Skip "No Token2 - SPONSOR tests will be skipped" }

# ============================================================================
# Phase 7.3: Initiation
# ============================================================================
Start-Sleep -Seconds 2

Section "P01: $User1Name creates project ($User2Name as SPONSOR) -> 200"
$ProjectId = $null
if ($Sub2) {
    $body = @{
        name        = "Test Project Alpha"
        sponsorId   = $Sub2
        startTarget = "2026-04-01"
        endTarget   = "2026-12-31"
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $ProjectId = ($r.Content | ConvertFrom-Json).id
        if ($ProjectId) { Pass "Project created id=$ProjectId" } else { Fail "No id in response: $($r.Content)" }
    } else {
        Fail "POST /api/projects -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No user2 sub for sponsorId" }

Section "P01a: GET /api/projects list -> includes created project"
if ($ProjectId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $projects = @($r.Content | ConvertFrom-Json)
        $found = $projects | Where-Object { $_.id -eq $ProjectId }
        if ($found) { Pass "List projects -> $($projects.Count) project(s), created project present" }
        else { Fail "Created project $ProjectId not found in list: $($r.Content)" }
    } else { Fail "GET /api/projects -> $(StatusOf $r): $($r.Content)" }
} else { Skip "No project from P01" }

Section "P01b: $User2Name (SPONSOR) can also list the project"
if ($ProjectId -and $Token2) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        $projects = @($r.Content | ConvertFrom-Json)
        $found = $projects | Where-Object { $_.id -eq $ProjectId }
        if ($found) { Pass "User2 list projects -> project visible (SPONSOR assignment works)" }
        else { Fail "Project $ProjectId not in user2's list: $($r.Content)" }
    } else { Fail "GET /api/projects as user2 -> $(StatusOf $r): $($r.Content)" }
} else { Skip "No project or Token2" }

Section "P02: $User1Name (PM) reads project -> 200"
if ($ProjectId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects/$ProjectId" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) { Pass "GET /api/projects/$ProjectId -> 200" } else { Fail "Expected 200, got $(StatusOf $r): $($r.Content)" }
} else { Skip "No project from P01" }

Section "P03: List project members -> PM and SPONSOR auto-assigned"
if ($ProjectId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects/$ProjectId/members" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $members    = @($r.Content | ConvertFrom-Json)
        $hasPm      = $members | Where-Object { $_.role -eq "PM" }
        $hasSponsor = $members | Where-Object { $_.role -eq "SPONSOR" }
        if ($hasPm -and $hasSponsor) {
            Pass "Members: $($members.Count) role(s) - PM and SPONSOR present"
        } else {
            Fail "Expected PM and SPONSOR, got: $(($members | ForEach-Object { $_.role }) -join ', ')"
        }
    } else {
        Fail "Expected 200, got $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P04: $User1Name (PM) creates project charter -> 200 (DRAFT)"
$CharterId = $null
if ($ProjectId) {
    $body = @{
        objectives      = "Deliver CRM project management module"
        highLevelScope  = "PMBOK-aligned Projects service"
        successCriteria = "All system tests green"
        summaryBudget   = 50000
        keyRisks        = "Integration complexity"
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/charter" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $CharterId = ($r.Content | ConvertFrom-Json).id
        $status    = ($r.Content | ConvertFrom-Json).status
        if ($CharterId) { Pass "Charter created id=$CharterId status=$status" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/charter -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P05: $User1Name (PM) submits charter -> 200 (SUBMITTED)"
if ($ProjectId -and $CharterId) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/charter/submit" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "SUBMITTED") { Pass "Charter submitted, status=$status" } else { Fail "Expected SUBMITTED, got $status" }
    } else {
        Fail "POST /api/projects/$ProjectId/charter/submit -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or charter" }

Section "P06: $User2Name (SPONSOR) approves charter -> 200 (project -> ACTIVE)"
if ($ProjectId -and $Auth2) {
    $body = @{ comment = "Charter approved" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/charter/approve" -Body $body -ContentType "application/json" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "APPROVED") { Pass "Charter approved, status=$status (project now ACTIVE)" } else { Fail "Expected APPROVED, got $status" }
    } else {
        Fail "POST /api/projects/$ProjectId/charter/approve -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or user2 token" }

Section "P07: Non-PM ($User2Name) blocked from submitting charter -> 403 or 400"
if ($ProjectId -and $Auth2) {
    # charter is already APPROVED; SPONSOR also lacks PM role -> 403 expected
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/charter/submit" -Body "" -ContentType "application/json" -Headers $Auth2
    if ($r -and ($r.StatusCode -eq 403 -or $r.StatusCode -eq 400)) {
        Pass "Non-PM charter/submit blocked -> $(StatusOf $r)"
    } else {
        Fail "Expected 403 or 400, got $(StatusOf $r)"
    }
} else { Skip "No project or user2 token" }

# ============================================================================
# Phase 7.4: Planning
# ============================================================================
Start-Sleep -Seconds 2

Section "P08: $User1Name (PM) creates WBS item -> 200"
$WbsItemId = $null
if ($ProjectId) {
    $body = @{ name = "1. Requirements"; wbsCode = "1.0"; description = "Gather and document requirements" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/wbs" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $WbsItemId = ($r.Content | ConvertFrom-Json).id
        if ($WbsItemId) { Pass "WBS item created id=$WbsItemId" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/wbs -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P09: $User1Name (PM) creates schedule task linked to WBS -> 200"
$TaskId = $null
if ($ProjectId) {
    $body = @{
        name       = "Implement auth module"
        wbsItemId  = $WbsItemId
        startDate  = "2026-04-01"
        endDate    = "2026-04-30"
        assigneeId = $Sub2
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/tasks" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $TaskId = ($r.Content | ConvertFrom-Json).id
        $status = ($r.Content | ConvertFrom-Json).status
        if ($TaskId) { Pass "Task created id=$TaskId status=$status" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/tasks -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P10: $User1Name (PM) creates cost item -> 200"
if ($ProjectId) {
    $body = @{ wbsItemId = $WbsItemId; category = "Labor"; plannedCost = 15000 } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/cost-items" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        Pass "Cost item created"
    } else {
        Fail "POST /api/projects/$ProjectId/cost-items -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P11: $User1Name (PM) creates baseline v1 (DRAFT, snapshotting WBS+tasks+costs) -> 200"
$BaselineV1 = $null
if ($ProjectId) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/baselines" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $json       = $r.Content | ConvertFrom-Json
        $BaselineV1 = $json.version
        $status     = $json.status
        if ($BaselineV1) { Pass "Baseline v$BaselineV1 created, status=$status" } else { Fail "No version in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/baselines -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P12: $User1Name (PM) submits baseline v1 -> 200 (SUBMITTED)"
if ($ProjectId -and $BaselineV1) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/baselines/$BaselineV1/submit" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "SUBMITTED") { Pass "Baseline v$BaselineV1 submitted, status=$status" } else { Fail "Expected SUBMITTED, got $status" }
    } else {
        Fail "POST .../baselines/$BaselineV1/submit -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or baseline v1" }

Section "P13: $User2Name (SPONSOR) approves baseline v1 -> 200 (APPROVED)"
if ($ProjectId -and $BaselineV1 -and $Auth2) {
    $body = @{ comment = "Baseline v1 approved" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/baselines/$BaselineV1/approve" -Body $body -ContentType "application/json" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "APPROVED") { Pass "Baseline v$BaselineV1 approved, status=$status" } else { Fail "Expected APPROVED, got $status" }
    } else {
        Fail "POST .../baselines/$BaselineV1/approve -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project, baseline v1, or user2 token" }

# ============================================================================
# Phase 7.5: Execution
# ============================================================================
Start-Sleep -Seconds 2

Section "P14: $User1Name (PM) creates deliverable -> 200 (PLANNED)"
$DeliverableId = $null
if ($ProjectId) {
    $body = @{
        name               = "Auth Module v1.0"
        dueDate            = "2026-05-15"
        acceptanceCriteria = "All auth system tests pass"
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/deliverables" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $DeliverableId = ($r.Content | ConvertFrom-Json).id
        $status        = ($r.Content | ConvertFrom-Json).status
        if ($DeliverableId) { Pass "Deliverable created id=$DeliverableId status=$status" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/deliverables -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P15: $User2Name (member) logs 8h work against task -> 200"
if ($ProjectId -and $TaskId -and $Auth2) {
    $body = @{ taskId = $TaskId; logDate = "2026-04-10"; hours = 8; note = "Auth setup complete" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/work-logs" -Body $body -ContentType "application/json" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        Pass "Work log created (8h)"
    } else {
        Fail "POST /api/projects/$ProjectId/work-logs -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project, task, or user2 token" }

Section "P16: List work logs for project -> includes logged entry"
if ($ProjectId -and $TaskId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects/$ProjectId/work-logs" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $count = @($r.Content | ConvertFrom-Json).Count
        if ($count -gt 0) { Pass "Work log list: $count entry/ies" } else { Fail "Expected >=1 work log, got 0" }
    } else {
        Fail "GET /api/projects/$ProjectId/work-logs -> $(StatusOf $r)"
    }
} else { Skip "No project or task" }

Section "P17: $User1Name (member) creates issue (HIGH severity) -> 200 (OPEN)"
$IssueId = $null
if ($ProjectId) {
    $body = @{ title = "Keycloak timeout on startup"; severity = "HIGH" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/issues" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $IssueId = ($r.Content | ConvertFrom-Json).id
        $status  = ($r.Content | ConvertFrom-Json).status
        if ($IssueId) { Pass "Issue created id=$IssueId status=$status" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/issues -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P18: $User1Name submits deliverable -> 200 (SUBMITTED)"
if ($ProjectId -and $DeliverableId) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/deliverables/$DeliverableId/submit" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "SUBMITTED") { Pass "Deliverable submitted, status=$status" } else { Fail "Expected SUBMITTED, got $status" }
    } else {
        Fail "POST .../deliverables/$DeliverableId/submit -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or deliverable" }

Section "P19: $User2Name (SPONSOR) accepts deliverable -> 200 (ACCEPTED)"
if ($ProjectId -and $DeliverableId -and $Auth2) {
    $body = @{ comment = "Accepted - all criteria met" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/deliverables/$DeliverableId/accept" -Body $body -ContentType "application/json" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "ACCEPTED") { Pass "Deliverable accepted, status=$status" } else { Fail "Expected ACCEPTED, got $status" }
    } else {
        Fail "POST .../deliverables/$DeliverableId/accept -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project, deliverable, or user2 token" }

Section "P20: Member updates task status -> IN_PROGRESS"
if ($ProjectId -and $TaskId) {
    $body = @{ status = "IN_PROGRESS" } | ConvertTo-Json -Compress
    $r = Invoke-Patch -Uri "$BaseUrl/api/projects/$ProjectId/tasks/$TaskId" -Body $body -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "IN_PROGRESS") { Pass "Task status -> $status" } else { Fail "Expected IN_PROGRESS, got $status" }
    } else {
        Fail "PATCH /api/projects/$ProjectId/tasks/$TaskId -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or task" }

# ============================================================================
# Phase 7.6: Monitoring & Controlling
# ============================================================================
Start-Sleep -Seconds 2

Section "P21: $User1Name creates SCOPE change request -> 200 (DRAFT)"
$CrId = $null
if ($ProjectId) {
    $body = @{
        type               = "SCOPE"
        description        = "Add reporting module to project scope"
        impactScope        = "New reporting bounded context required"
        impactScheduleDays = 14
        impactCost         = 5000
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/change-requests" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $CrId   = ($r.Content | ConvertFrom-Json).id
        $status = ($r.Content | ConvertFrom-Json).status
        if ($CrId) { Pass "CR created id=$CrId status=$status" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/change-requests -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P22: Submit CR -> 200 (SUBMITTED)"
if ($ProjectId -and $CrId) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/change-requests/$CrId/submit" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "SUBMITTED") { Pass "CR submitted, status=$status" } else { Fail "Expected SUBMITTED, got $status" }
    } else {
        Fail "POST .../change-requests/$CrId/submit -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or CR" }

Section "P23: $User1Name (PM) moves CR to IN_REVIEW -> 200"
if ($ProjectId -and $CrId) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/change-requests/$CrId/review" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "IN_REVIEW") { Pass "CR in review, status=$status" } else { Fail "Expected IN_REVIEW, got $status" }
    } else {
        Fail "POST .../change-requests/$CrId/review -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or CR" }

Section "P24: $User1Name (PM) approves CR -> 200 (APPROVED, auto-creates baseline v2 DRAFT)"
if ($ProjectId -and $CrId) {
    $body = @{ comment = "Scope increase approved" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/change-requests/$CrId/approve" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "APPROVED") { Pass "CR approved, status=$status" } else { Fail "Expected APPROVED, got $status" }
    } else {
        Fail "POST .../change-requests/$CrId/approve -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or CR" }

Section "P25: Baseline v2 auto-created (DRAFT) and linked to CR"
$BaselineV2 = $null
if ($ProjectId -and $CrId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects/$ProjectId/baselines" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $baselines = $r.Content | ConvertFrom-Json
        $linked    = $baselines | Where-Object { $_.changeRequestId -eq $CrId }
        if ($linked) {
            $BaselineV2 = $linked.version
            Pass "Baseline v$BaselineV2 linked to CR, status=$($linked.status)"
        } else {
            Fail "No baseline linked to CR $CrId. Baselines: $(($baselines | ForEach-Object { "v$($_.version)/$($_.status)" }) -join ', ')"
        }
    } else {
        Fail "GET /api/projects/$ProjectId/baselines -> $(StatusOf $r)"
    }
} else { Skip "No project or CR" }

Section "P26: $User1Name (PM) submits baseline v2 -> 200 (SUBMITTED)"
if ($ProjectId -and $BaselineV2) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/baselines/$BaselineV2/submit" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "SUBMITTED") { Pass "Baseline v$BaselineV2 submitted, status=$status" } else { Fail "Expected SUBMITTED, got $status" }
    } else {
        Fail "POST .../baselines/$BaselineV2/submit -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or baseline v2" }

Section "P27: $User2Name (SPONSOR) approves baseline v2 -> 200 (APPROVED)"
if ($ProjectId -and $BaselineV2 -and $Auth2) {
    $body = @{ comment = "Revised baseline approved" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/baselines/$BaselineV2/approve" -Body $body -ContentType "application/json" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "APPROVED") { Pass "Baseline v$BaselineV2 approved, status=$status" } else { Fail "Expected APPROVED, got $status" }
    } else {
        Fail "POST .../baselines/$BaselineV2/approve -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project, baseline v2, or user2 token" }

Section "P28: $User1Name (PM) implements CR -> 200 (IMPLEMENTED)"
if ($ProjectId -and $CrId) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/change-requests/$CrId/implement" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "IMPLEMENTED") { Pass "CR implemented, status=$status" } else { Fail "Expected IMPLEMENTED, got $status" }
    } else {
        Fail "POST .../change-requests/$CrId/implement -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or CR" }

# Allow rate-limit bucket to refill after the rapid P21-P28 burst
Start-Sleep -Seconds 2

Section "P29: $User1Name (PM) creates decision log -> 200"
if ($ProjectId) {
    $body = @{
        decision     = "Adopt Spring Cloud Config for centralised configuration"
        decisionDate = "2026-04-15"
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/decisions" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        Pass "Decision log created"
    } else {
        Fail "POST /api/projects/$ProjectId/decisions -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P30: $User1Name (PM) creates status report (ragScope=AMBER) -> 200"
$ReportId = $null
if ($ProjectId) {
    $body = @{
        periodStart = "2026-04-01"
        periodEnd   = "2026-04-30"
        summary     = "Auth module complete. Scope CR approved and implemented."
        ragScope    = "AMBER"
        ragSchedule = "GREEN"
        ragCost     = "GREEN"
        keyRisks    = "Integration with legacy systems"
        keyIssues   = "Keycloak timeout resolved"
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/status-reports" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $ReportId  = ($r.Content | ConvertFrom-Json).id
        $ragScope  = ($r.Content | ConvertFrom-Json).ragScope
        if ($ReportId) { Pass "Status report created id=$ReportId ragScope=$ragScope" } else { Fail "No id in response" }
    } else {
        Fail "POST /api/projects/$ProjectId/status-reports -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P31: List change requests -> CR is IMPLEMENTED"
if ($ProjectId -and $CrId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects/$ProjectId/change-requests" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $crs   = @($r.Content | ConvertFrom-Json)
        $found = $crs | Where-Object { $_.id -eq $CrId }
        if ($found -and $found.status -eq "IMPLEMENTED") {
            Pass "CR list: $($crs.Count) entry/ies, CR status=$($found.status)"
        } else {
            $got = if ($found) { $found.status } else { "not found" }
            Fail "Expected CR IMPLEMENTED, got: $got"
        }
    } else {
        Fail "GET /api/projects/$ProjectId/change-requests -> $(StatusOf $r)"
    }
} else { Skip "No project or CR" }

Section "P32: List status reports -> most recent first, includes AMBER report"
if ($ProjectId -and $ReportId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects/$ProjectId/status-reports" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $reports = @($r.Content | ConvertFrom-Json)
        $found   = $reports | Where-Object { $_.id -eq $ReportId }
        if ($found -and $found.ragScope -eq "AMBER") {
            Pass "Status reports: $($reports.Count) report(s), report ragScope=$($found.ragScope)"
        } else {
            Fail "Expected report with ragScope=AMBER, got: $(($reports | ForEach-Object { $_.ragScope }) -join ', ')"
        }
    } else {
        Fail "GET /api/projects/$ProjectId/status-reports -> $(StatusOf $r)"
    }
} else { Skip "No project or report" }


# ============================================================================
# PHASE 7.7 — CLOSING
# ============================================================================

Section "P33: $User1Name (PM) creates closure report -> 200 (DRAFT)"
$ClosureReportId = $null
if ($ProjectId) {
    $body = @{
        outcomesSummary   = "All deliverables accepted, scope achieved."
        budgetActual      = 95000.00
        scheduleActual    = "Completed 2 days ahead of schedule"
        acceptanceSummary = "All deliverables formally accepted by sponsor."
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/closure-report" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $obj = $r.Content | ConvertFrom-Json
        $ClosureReportId = $obj.id
        if ($obj.status -eq "DRAFT") { Pass "Closure report created id=$ClosureReportId status=DRAFT" }
        else { Fail "Expected status DRAFT, got $($obj.status)" }
    } else {
        Fail "POST /api/projects/$ProjectId/closure-report -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P34: $User1Name (PM) adds lesson learned -> 200"
$LessonId = $null
if ($ProjectId) {
    $body = @{
        category       = "Planning"
        whatHappened   = "Early stakeholder alignment reduced rework by 30%."
        recommendation = "Hold stakeholder alignment workshop at project kick-off."
    } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/lessons-learned" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $LessonId = ($r.Content | ConvertFrom-Json).id
        Pass "Lesson learned created id=$LessonId"
    } else {
        Fail "POST /api/projects/$ProjectId/lessons-learned -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project from P01" }

Section "P35: $User1Name (PM) submits closure report -> 200 (SUBMITTED)"
if ($ProjectId -and $ClosureReportId) {
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/closure-report/submit" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "SUBMITTED") { Pass "Closure report submitted, status=$status" }
        else { Fail "Expected SUBMITTED, got $status" }
    } else {
        Fail "POST .../closure-report/submit -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or closure report" }

Section "P36: $User1Name (PM) blocked from approving own closure report -> 403"
if ($ProjectId -and $ClosureReportId) {
    $body = @{ comment = "Self-approval attempt" } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/closure-report/approve" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 403) { Pass "PM closure-report/approve blocked -> 403" }
    else { Fail "Expected 403 (PM not SPONSOR), got $(StatusOf $r)" }
} else { Skip "No project or closure report" }

Section "P37: testuser2 (SPONSOR) approves closure report -> 200 (APPROVED)"
if ($ProjectId -and $ClosureReportId) {
    $body = @{ comment = "All deliverables verified. Project formally closed." } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/closure-report/approve" -Body $body -ContentType "application/json" -Headers $Auth2
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "APPROVED") { Pass "Closure report approved, status=$status" }
        else { Fail "Expected APPROVED, got $status" }
    } else {
        Fail "POST .../closure-report/approve -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or closure report" }

Section "P38: $User1Name (PM) closes project before all deliverables accepted -> 400"
# Deliverable was ACCEPTED in P19, so this should actually succeed if checked.
# Create a new unaccepted deliverable to trigger the gate rejection.
$BlockingDeliverableId = $null
if ($ProjectId) {
    $body = @{ name = "Unaccepted deliverable (gate test)"; acceptanceCriteria = "Will not be accepted." } | ConvertTo-Json -Compress
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/deliverables" -Body $body -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $BlockingDeliverableId = ($r.Content | ConvertFrom-Json).id
        $r2 = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/close" -Body "" -ContentType "application/json" -Headers $Auth1
        if ($r2 -and $r2.StatusCode -eq 400) { Pass "Close blocked: unaccepted deliverable -> 400" }
        else { Fail "Expected 400 (unaccepted deliverable), got $(StatusOf $r2)" }
    } else {
        Skip "Could not create blocking deliverable ($(StatusOf $r)) — skipping gate test"
    }
} else { Skip "No project from P01" }

Section "P39: Accept blocking deliverable, then close project -> 200 (CLOSED)"
if ($ProjectId -and $BlockingDeliverableId) {
    # Submit then accept the blocking deliverable
    Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/deliverables/$BlockingDeliverableId/submit" -Body "" -ContentType "application/json" -Headers $Auth1 | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/deliverables/$BlockingDeliverableId/accept" -Body "" -ContentType "application/json" -Headers $Auth2 | Out-Null
    Start-Sleep -Milliseconds 300
    $r = Invoke-Post -Uri "$BaseUrl/api/projects/$ProjectId/close" -Body "" -ContentType "application/json" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $status = ($r.Content | ConvertFrom-Json).status
        if ($status -eq "CLOSED") { Pass "Project closed, status=$status" }
        else { Fail "Expected CLOSED, got $status" }
    } else {
        Fail "POST /api/projects/$ProjectId/close -> $(StatusOf $r): $($r.Content)"
    }
} else { Skip "No project or blocking deliverable" }

Section "P40: List lessons learned -> includes added lesson"
if ($ProjectId -and $LessonId) {
    $r = Invoke-Get -Uri "$BaseUrl/api/projects/$ProjectId/lessons-learned" -Headers $Auth1
    if ($r -and $r.StatusCode -eq 200) {
        $lessons = @($r.Content | ConvertFrom-Json)
        $found   = $lessons | Where-Object { $_.id -eq $LessonId }
        if ($found) { Pass "Lessons learned: $($lessons.Count) entry/ies, lesson found" }
        else { Fail "Lesson $LessonId not found in list" }
    } else {
        Fail "GET /api/projects/$ProjectId/lessons-learned -> $(StatusOf $r)"
    }
} else { Skip "No project or lesson" }

} # end -not $SkipPMBOK

# ============================================================================
# RATE LIMITING (optional)
# ============================================================================
if ($RateLimit) {
    Section "TRL: Rate limiting -> expect HTTP 429 after burst"
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

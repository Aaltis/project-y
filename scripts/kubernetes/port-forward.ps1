# port-forward.ps1 — Manage kubectl port-forward for ingress-nginx in the background
#
# Usage:
#   .\port-forward.ps1 start    — Start port-forward in background (auto-restarts on drop)
#   .\port-forward.ps1 stop     — Stop the background port-forward
#   .\port-forward.ps1 status   — Show whether it is running

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action
)

$PidFile = "$env:TEMP\kube-port-forward.pid"
$Port    = 8080
$Svc     = "svc/ingress-nginx-controller"
$Ns      = "ingress-nginx"

function Get-SavedPid {
    if (Test-Path $PidFile) {
        return [int](Get-Content $PidFile)
    }
    return $null
}

function Test-ProcessRunning($id) {
    if ($null -eq $id) { return $false }
    return $null -ne (Get-Process -Id $id -ErrorAction SilentlyContinue)
}

switch ($Action) {

    "start" {
        $existing = Get-SavedPid
        if (Test-ProcessRunning $existing) {
            Write-Host "Already running (PID $existing). Use 'stop' first if you want to restart." -ForegroundColor Yellow
            exit 0
        }

        # Check port is free; if not, show what owns it
        $listening = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING" | Select-Object -First 1
        if ($listening) {
            $ownerPid  = ($listening -split '\s+')[-1]
            $ownerProc = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
            $ownerName = if ($ownerProc) { $ownerProc.Name } else { "unknown" }
            Write-Host "Port $Port is already in use by '$ownerName' (PID $ownerPid)." -ForegroundColor Yellow
            if ($ownerName -match "kubectl") {
                Write-Host "It looks like port-forward is already running (untracked). Adopting it." -ForegroundColor Green
                $ownerPid | Set-Content $PidFile
                exit 0
            }
            Write-Host "Kill it with:  Stop-Process -Id $ownerPid -Force" -ForegroundColor Yellow
            exit 1
        }

        # Launch a hidden PowerShell process that loops forever and restarts the forward on drop
        $cmd = "while (`$true) { kubectl port-forward $Svc ${Port}:80 -n $Ns; Start-Sleep 2 }"
        $proc = Start-Process powershell `
            -ArgumentList "-WindowStyle", "Hidden", "-NoProfile", "-Command", $cmd `
            -PassThru

        $proc.Id | Set-Content $PidFile
        Write-Host "Port-forward started in background (PID $($proc.Id))." -ForegroundColor Green
        Write-Host "Traffic on http://localhost:$Port is now routed to $Svc."
    }

    "stop" {
        $existing = Get-SavedPid
        if (-not (Test-ProcessRunning $existing)) {
            Write-Host "No running port-forward found." -ForegroundColor Yellow
            if (Test-Path $PidFile) { Remove-Item $PidFile }
            exit 0
        }

        # Kill the wrapper process and any kubectl child it spawned
        $proc = Get-Process -Id $existing -ErrorAction SilentlyContinue
        if ($proc) {
            # Kill child kubectl processes first
            Get-WmiObject Win32_Process | Where-Object { $_.ParentProcessId -eq $existing } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Stop-Process -Id $existing -Force
        }

        Remove-Item $PidFile -ErrorAction SilentlyContinue
        Write-Host "Port-forward stopped." -ForegroundColor Green
    }

    "status" {
        $existing = Get-SavedPid
        if (Test-ProcessRunning $existing) {
            Write-Host "Running (PID $existing) - http://localhost:$Port" -ForegroundColor Green
        } else {
            Write-Host "Not running." -ForegroundColor Yellow
            if (Test-Path $PidFile) { Remove-Item $PidFile }
        }
    }
}

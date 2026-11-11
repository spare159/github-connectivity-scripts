# Apply GitHub hosts mapping - must run as Administrator
# Adds a verified working GitHub web IP; original hosts is backed up first.

$hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$backup    = Join-Path $PSScriptRoot "hosts.backup.txt"
$log       = Join-Path $PSScriptRoot "github-hosts-result.txt"
$ip        = "20.87.245.0"

try {
    Copy-Item -Path $hostsPath -Destination $backup -Force
    $existing = Get-Content -Path $hostsPath
    $has = $existing | Where-Object { $_ -match '^\s*\d+\.\d+\.\d+\.\d+\s+github\.com\s*$' }
    if (-not $has) {
        Add-Content -Path $hostsPath -Value "" -Encoding ASCII
        Add-Content -Path $hostsPath -Value "# GitHub web IP (WorkBuddy 2026-11-11)" -Encoding ASCII
        Add-Content -Path $hostsPath -Value "$ip github.com" -Encoding ASCII
    }
    & ipconfig /flushdns | Out-Null
    $check = (Get-Content -Path $hostsPath | Where-Object { $_ -match 'github\.com' }) -join " | "
    "OK`nmapping=$check`nbackup=$backup" | Set-Content -Path $log -Encoding ASCII
} catch {
    "FAILED: $($_.Exception.Message)" | Set-Content -Path $log -Encoding ASCII
}

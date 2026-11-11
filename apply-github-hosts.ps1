# Apply GitHub hosts mapping - must run as Administrator
# Probes official GitHub web IPs, picks one that currently returns 200,
# backs up hosts, replaces any old github.com mapping, then flushes DNS.

$hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$backup    = Join-Path $PSScriptRoot "hosts.backup.txt"
$log       = Join-Path $PSScriptRoot "github-hosts-result.txt"
$ips       = @('20.87.245.0','20.29.134.23','20.207.73.82','4.237.22.38','20.233.83.145','20.200.245.247','20.175.192.147')

try {
    Copy-Item -Path $hostsPath -Destination $backup -Force

    Write-Host "Probing GitHub web IPs ..."
    $best = $null
    foreach ($ip in $ips) {
        $code = & curl.exe --noproxy "*" --ssl-no-revoke --resolve "github.com:443:$ip" -s -o NUL -w "%{http_code}" -m 4 https://github.com/login 2>$null
        Write-Host "  $ip -> $code"
        if ($code -eq "200") { $best = $ip; break }
    }
    if (-not $best) {
        $best = $ips[0]
        Write-Host "No IP returned 200; using fallback $best"
    }

    $lines = Get-Content -Path $hostsPath
    $kept = $lines | Where-Object {
        $_ -notmatch '^\s*#?\s*\d+\.\d+\.\d+\.\d+\s+github\.com\s*$' -and
        $_ -notmatch 'GitHub web IP \(WorkBuddy'
    }
    $new = @($kept) + @("", "# GitHub web IP (WorkBuddy 2026-11-11)", "$best github.com")
    Set-Content -Path $hostsPath -Value $new -Encoding ASCII
    & ipconfig /flushdns | Out-Null

    $check = (Get-Content -Path $hostsPath | Where-Object { $_ -match 'github\.com' }) -join " | "
    Write-Host ""
    Write-Host "DONE: $check"
    Write-Host "Backup saved to: $backup"
    "OK`nip=$best`nbackup=$backup" | Set-Content -Path $log -Encoding ASCII
} catch {
    Write-Host "FAILED: $($_.Exception.Message)"
    "FAILED: $($_.Exception.Message)" | Set-Content -Path $log -Encoding ASCII
}

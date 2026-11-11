# Open a GitHub authorization URL in the fixed-IP Edge window.
# Step 1: copy the full URL from the default browser address bar.
# Step 2: run this script (or double-click open-auth-in-fixed-edge.bat).

$edge    = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$profile = Join-Path $env:TEMP "gh-edge"
$ips     = @('20.87.245.0','20.29.134.23','20.207.73.82','4.237.22.38','20.233.83.145','20.200.245.247','20.175.192.147')

Write-Host "=== Open GitHub authorization in fixed-IP Edge ==="

$url = (Get-Clipboard -Raw)
if ([string]::IsNullOrWhiteSpace($url)) {
    Write-Host "Clipboard is empty. Copy the full authorize URL from the default browser address bar first."
    Read-Host "Press Enter to exit"
    exit 1
}
$url = $url.Trim()
if ($url -notmatch '^https://github\.com/') {
    Write-Host "Clipboard content is not a github.com URL:"
    Write-Host $url
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Picking a currently reachable GitHub IP ..."
$best = $null
foreach ($ip in $ips) {
    $code = & curl.exe --noproxy "*" --ssl-no-revoke --resolve "github.com:443:$ip" -s -o NUL -w "%{http_code}" -m 4 https://github.com/login 2>$null
    Write-Host "  $ip -> $code"
    if ($code -eq "200") { $best = $ip; break }
}
if (-not $best) {
    $best = $ips[0]
    Write-Host "No IP returned 200; falling back to $best"
}

Write-Host "Using IP: $best"
Write-Host "Opening: $url"
Write-Host ""
Write-Host "In that Edge window: sign in to GitHub, then click the green Authorize button."
Write-Host "If Edge asks to open WorkBuddy for the callback, click Allow/Open."

# Same --user-data-dir means Edge forwards the URL to the already-running window.
& $edge --host-resolver-rules="MAP github.com $best" --user-data-dir="$profile" $url

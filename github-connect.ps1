# GitHub Login Connector
# Retries until github.com/login becomes reachable, then opens the login page.
# Run: powershell -ExecutionPolicy Bypass -File "github-connect.ps1"

$maxTries = 40
$waitSec  = 5
$testUrl  = "https://github.com/login"

Write-Host "=== GitHub Login Connector ==="
Write-Host "Checking github.com ... (up to $maxTries tries, $waitSec s apart)"
Write-Host "Keep this network connected. Press Ctrl+C to stop."
Write-Host ""

for ($i = 1; $i -le $maxTries; $i++) {
    $code = & curl.exe --noproxy "*" --ssl-no-revoke -s -o NUL -w "%{http_code}" -m 8 $testUrl 2>$null
    if ($code -eq "200") {
        Write-Host "[OK] github.com is reachable (try $i/$maxTries)."
        Write-Host "Opening the login page in your default browser now..."
        Start-Process "https://github.com/login"
        Write-Host "If the page still spins, press Ctrl+F5 a few times."
        exit 0
    }
    Write-Host ("[{0}/{1}] not reachable (http={2}) - retry in {3}s" -f $i, $maxTries, $code, $waitSec)
    Start-Sleep -Seconds $waitSec
}

Write-Host ""
Write-Host "[FAILED] github.com stayed unreachable after $maxTries tries."
Write-Host "This is a network-path block, not an account problem. Try:"
Write-Host "  1) Open github.com/login directly in your PHONE browser (not via hotspot)."
Write-Host "  2) Switch to another network, or enable a working proxy with system proxy ON."
Write-Host "  3) Rerun this script after changing network."
exit 1

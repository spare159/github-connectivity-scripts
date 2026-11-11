param(
    [string]$TokenFile = (Join-Path $PSScriptRoot '.git-token'),
    [string]$RepoName  = 'github-connectivity-scripts',
    [string]$Branch    = 'main',
    [string]$GitExe    = '',
    [switch]$ApiOnly
)

# Upload this local repository to GitHub using a Personal Access Token.
# The token is read from a LOCAL file only: never printed, never committed.
#
# Two independent paths:
#   1) git push over https://github.com  (keeps local commit history)
#   2) REST API upload via api.github.com (fallback; github.com may be blocked)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\push-to-github.ps1
#   powershell -ExecutionPolicy Bypass -File .\push-to-github.ps1 -ApiOnly
#
# If .git-token is missing, this script opens the pre-filled token page for you.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tokenPage = 'https://github.com/settings/tokens/new?description=WorkBuddy&scopes=repo'

if (-not (Test-Path $TokenFile)) {
    Write-Host "No token file yet: $TokenFile" -ForegroundColor Yellow
    Write-Host "Opening the GitHub token page in your default browser..."
    Write-Host "URL: $tokenPage"
    try { Start-Process $tokenPage } catch { Write-Host "(Could not open browser; copy the URL above.)" }
    Write-Host ""
    Write-Host "Steps: log in -> name the token -> make sure 'repo' is checked -> Generate token"
    Write-Host "       -> copy it -> save ONLY the token, one line, into .git-token"
    Write-Host "       -> run this script again."
    Write-Host "If github.com will not load, open that URL from your phone's mobile data."
    exit 1
}

$token = (Get-Content $TokenFile -Raw).Trim()
if ($token.Length -lt 20) {
    Write-Host "ERROR: token looks too short. Check .git-token contents." -ForegroundColor Red
    exit 1
}
Write-Host "Token loaded from local file (length $($token.Length)), content hidden."

$headers = @{
    Authorization = "Bearer $token"
    Accept        = 'application/vnd.github+json'
    'User-Agent'  = 'WorkBuddy'
}

function Invoke-GitHub {
    param([string]$Uri, [string]$Method = 'Get', [object]$Body = $null)
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 5
        return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -Body $json -ContentType 'application/json' -TimeoutSec 25
    }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -TimeoutSec 25
}

# --- 1. Identify the GitHub account (api.github.com is reliably reachable) ---
try {
    $user = Invoke-GitHub -Uri 'https://api.github.com/user'
} catch {
    Write-Host "ERROR: GitHub API rejected the token (invalid token, or network failure)." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
$login = $user.login
Write-Host "Authenticated as: $login"

# --- 2. Create the repo if it does not exist ---
$exists = $false
try {
    $null = Invoke-GitHub -Uri "https://api.github.com/repos/$login/$RepoName"
    $exists = $true
} catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($status -ne 404) {
        Write-Host "ERROR: could not check repository (HTTP $status)." -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }
}

if (-not $exists) {
    try {
        $null = Invoke-GitHub -Uri 'https://api.github.com/user/repos' -Method 'Post' -Body @{
            name        = $RepoName
            description = 'GitHub connectivity troubleshooting scripts'
            private     = $false
            auto_init   = $false
        }
        Write-Host "Created repository: $login/$RepoName"
    } catch {
        Write-Host "ERROR: failed to create repository. Check that the token has the 'repo' scope." -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }
} else {
    Write-Host "Repository already exists: $login/$RepoName"
}

$repoUrl = "https://github.com/$login/$RepoName"

# --- 3. Locate git.exe (a plain PowerShell session may not inherit the bundled Git PATH) ---
if (-not $GitExe) {
    $found = Get-Command git -ErrorAction SilentlyContinue
    if ($found) { $GitExe = $found.Source }
}
if (-not $GitExe) {
    # Derive from this script's parent dir so no non-ASCII literals are needed.
    $parentDir = Split-Path $PSScriptRoot -Parent
    $candidates = @(
        (Join-Path $parentDir 'WorkBuddy\resources\vendor\PortableGit\mingw64\bin\git.exe'),
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files (x86)\Git\cmd\git.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $GitExe = $c; break } }
}

# --- 4. Path 1: git push (preserves local commit history) ---
$pushed = $false
if (-not $ApiOnly -and $GitExe) {
    Write-Host ""
    Write-Host "[Path 1] git push (keeping local commit history)..." -ForegroundColor Cyan
    & $GitExe -C $PSScriptRoot remote remove origin 2>$null | Out-Null
    & $GitExe -C $PSScriptRoot remote add origin "$repoUrl.git" 2>$null | Out-Null
    $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
    for ($i = 1; $i -le 3; $i++) {
        Write-Host "  attempt $i/3 ..."
        $out = & $GitExe -C $PSScriptRoot -c http.sslBackend=openssl -c "http.extraHeader=AUTHORIZATION: Basic $b64" push -u origin $Branch 2>&1
        if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
    }
    if (-not $pushed) { Write-Host "  git push unavailable (github.com link is flaky)." -ForegroundColor Yellow }
} elseif ($ApiOnly) {
    Write-Host ""
    Write-Host "[Path 1] skipped (-ApiOnly)." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "[Path 1] skipped (git.exe not found)." -ForegroundColor Yellow
}

# --- 5. Path 2: REST API upload (only api.github.com needed) ---
if (-not $pushed) {
    Write-Host ""
    Write-Host "[Path 2] uploading files via api.github.com ..." -ForegroundColor Cyan
    if (-not $GitExe) {
        $files = Get-ChildItem -Path $PSScriptRoot -File | Where-Object { $_.Name -notmatch '^\.' -and $_.Name -notin @('hosts.backup.txt','github-hosts-result.txt','push-to-github.ps1') } | Select-Object -ExpandProperty Name
        $files += '.gitignore'
    } else {
        $files = & $GitExe -C $PSScriptRoot ls-files
        if ($LASTEXITCODE -ne 0) { $files = @() }
    }

    $uploaded = 0
    $failed = 0
    foreach ($rel in $files) {
        $rel = ($rel -replace '/', '\').Trim()
        if (-not $rel) { continue }
        $full = Join-Path $PSScriptRoot $rel
        if (-not (Test-Path $full)) { continue }
        $apiPath = $rel -replace '\\', '/'
        $uri = "https://api.github.com/repos/$login/$RepoName/contents/$apiPath"

        # If the file already exists, PUT needs its current sha.
        $sha = $null
        try {
            $cur = Invoke-GitHub -Uri $uri
            if ($cur.sha) { $sha = $cur.sha }
        } catch { }

        $payload = @{
            message = "Add/update $apiPath via WorkBuddy"
            content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($full))
        }
        if ($sha) { $payload.sha = $sha }

        try {
            $null = Invoke-GitHub -Uri $uri -Method 'Put' -Body $payload
            Write-Host "  OK   $apiPath"
            $uploaded++
        } catch {
            Write-Host "  FAIL $apiPath : $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }
    Write-Host "  uploaded=$uploaded failed=$failed"
    if ($uploaded -eq 0) {
        Write-Host ""
        Write-Host "ERROR: no files could be uploaded." -ForegroundColor Red
        exit 1
    }
    Write-Host "NOTE: API uploads create one commit per file (local history is not preserved)." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "SUCCESS: https://github.com/$login/$RepoName" -ForegroundColor Green
Write-Host "Local commits kept: $(if ($pushed) { 'yes' } else { 'no (API upload)' })"

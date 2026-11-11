param(
    [string]$TokenFile = (Join-Path $PSScriptRoot '.git-token'),
    [string]$RepoName  = 'github-connectivity-scripts',
    [string]$Branch    = 'main',
    [string]$GitExe    = ''
)

# Push this local repository to GitHub using a Personal Access Token.
# The token is read from a LOCAL file only: never printed, never committed.
# Usage:
#   1) Create a token at https://github.com/settings/tokens  (scope: repo)
#   2) Save ONLY the token string into .git-token (same folder, one line)
#   3) Run:  powershell -ExecutionPolicy Bypass -File .\push-to-github.ps1

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Locate git.exe (a plain PowerShell session may not inherit the bundled Git PATH) ---
if (-not $GitExe) {
    $found = Get-Command git -ErrorAction SilentlyContinue
    if ($found) { $GitExe = $found.Source }
}
if (-not $GitExe) {
    # Derive from this script's parent directory so no non-ASCII literals are needed.
    $parentDir = Split-Path $PSScriptRoot -Parent
    $candidates = @(
        (Join-Path $parentDir 'WorkBuddy\resources\vendor\PortableGit\mingw64\bin\git.exe'),
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files (x86)\Git\cmd\git.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $GitExe = $c; break } }
}
if (-not $GitExe) {
    Write-Host "ERROR: git.exe not found. Re-run with -GitExe 'C:\path\to\git.exe'." -ForegroundColor Red
    exit 1
}
Write-Host "git: $GitExe"

if (-not (Test-Path $TokenFile)) {
    Write-Host "ERROR: token file not found: $TokenFile" -ForegroundColor Red
    Write-Host "Create it first: put your GitHub token on a single line in that file."
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

# --- 1. Identify the GitHub account ---
try {
    $user = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers -Method Get -TimeoutSec 20
} catch {
    Write-Host "ERROR: GitHub API rejected the token (auth or network failure)." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
$login = $user.login
Write-Host "Authenticated as: $login"

# --- 2. Create the repo if it does not exist ---
$exists = $false
try {
    $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$login/$RepoName" -Headers $headers -Method Get -TimeoutSec 20
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
    $body = @{
        name        = $RepoName
        description = 'GitHub connectivity troubleshooting scripts'
        private     = $false
        auto_init   = $false
    } | ConvertTo-Json
    try {
        $null = Invoke-RestMethod -Uri 'https://api.github.com/user/repos' -Headers $headers -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 20
        Write-Host "Created repository: $login/$RepoName"
    } catch {
        Write-Host "ERROR: failed to create repository. Check that the token has the 'repo' scope." -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }
} else {
    Write-Host "Repository already exists: $login/$RepoName"
}

# --- 3. Point origin at the clean URL (NO credentials stored in .git/config) ---
$repoUrl = "https://github.com/$login/$RepoName.git"
& $GitExe -C $PSScriptRoot remote remove origin 2>$null | Out-Null
& $GitExe -C $PSScriptRoot remote add origin $repoUrl
Write-Host "Remote origin -> $repoUrl"

# --- 4. Push using a per-process auth header (token never written to disk) ---
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
$ok = $false
for ($i = 1; $i -le 3; $i++) {
    Write-Host "Push attempt $i/3 ..."
    $out = & $GitExe -C $PSScriptRoot -c http.sslBackend=openssl -c "http.extraHeader=AUTHORIZATION: Basic $b64" push -u origin $Branch 2>&1
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Write-Host ($out | Select-Object -Last 4)
}

if ($ok) {
    Write-Host ""
    Write-Host "SUCCESS: pushed to https://github.com/$login/$RepoName" -ForegroundColor Green
    & $GitExe -C $PSScriptRoot log --oneline -3
} else {
    Write-Host ""
    Write-Host "Push failed after 3 attempts (link is flaky). Re-run this script to retry." -ForegroundColor Red
    exit 1
}

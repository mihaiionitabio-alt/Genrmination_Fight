<#
    Commit whatever is currently in the working tree and push it to GitHub.

    Run AFTER tools/capture.lua has refreshed src/ from Studio:
        .\tools\push-update.ps1 "what changed"

    Shows the diff and asks before committing, so a bad capture cannot be
    pushed by reflex.
#>
param([Parameter(Mandatory = $true)][string]$Message)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$changed = git status --porcelain
if (-not $changed) { Write-Host "Nothing has changed." -ForegroundColor Yellow; exit 0 }

Write-Host "`nFiles changed:" -ForegroundColor Cyan
git status --short
Write-Host "`nLine counts:" -ForegroundColor Cyan
git diff --stat
git diff --cached --stat

# A capture that silently wrote nothing is the failure mode worth catching:
# src/ emptying out looks like a huge, plausible-looking diff.
$deleted = (git status --porcelain src | Select-String '^ ?D').Count
if ($deleted -gt 0) {
    Write-Host "`n$deleted script(s) would be DELETED from src/." -ForegroundColor Red
    Write-Host "If you did not delete them in Studio, the capture failed - stop here." -ForegroundColor Red
}

$reply = Read-Host "`nCommit and push? (y/N)"
if ($reply -ne "y") { Write-Host "Nothing committed." -ForegroundColor Yellow; exit 0 }

git add -A
git commit -m $Message
git push origin main
Write-Host "`nPushed. https://github.com/mihaiionitabio-alt/Genrmination_Fight" -ForegroundColor Green

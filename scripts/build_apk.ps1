# Script tự động tăng version và build APK
# Usage: .\scripts\build_apk.ps1 [patch|minor|major] [--no-version-bump]

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("patch", "minor", "major")]
    [string]$VersionType = "patch",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoVersionBump = $false
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Synap - Auto Build APK Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Bước 1: Tăng version (nếu không có flag --no-version-bump)
if (-not $NoVersionBump) {
    Write-Host "Step 1: Bumping version ($VersionType)..." -ForegroundColor Yellow
    & ".\scripts\version_bump.ps1" -Type $VersionType
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to bump version!" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
} else {
    Write-Host "Step 1: Skipping version bump (--no-version-bump flag)" -ForegroundColor Yellow
    Write-Host ""
}

# Bước 2: Clean build
Write-Host "Step 2: Cleaning build..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: flutter clean failed!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Bước 3: Get dependencies
Write-Host "Step 3: Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: flutter pub get failed!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Bước 4: Build APK
Write-Host "Step 4: Building APK (release)..." -ForegroundColor Yellow
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Bước 5: Hiển thị thông tin
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Build completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "APK location:" -ForegroundColor Cyan
Write-Host "  build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor White
Write-Host ""
Write-Host "To install on device:" -ForegroundColor Cyan
Write-Host "  adb install build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor White
Write-Host ""


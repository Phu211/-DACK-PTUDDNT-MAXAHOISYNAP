# PowerShell script để tăng version trong pubspec.yaml
# Usage: .\scripts\version_bump.ps1 [major|minor|patch]

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("major", "minor", "patch")]
    [string]$Type
)

$pubspecPath = "pubspec.yaml"

if (-not (Test-Path $pubspecPath)) {
    Write-Host "Error: pubspec.yaml not found!" -ForegroundColor Red
    exit 1
}

# Đọc file pubspec.yaml
$content = Get-Content $pubspecPath -Raw

# Tìm dòng version
if ($content -match "version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)") {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]
    $versionCode = [int]$matches[4]
    
    Write-Host "Current version: $major.$minor.$patch+$versionCode" -ForegroundColor Cyan
    
    # Tăng version theo type
    switch ($Type) {
        "major" {
            $major++
            $minor = 0
            $patch = 0
            Write-Host "Bumping MAJOR version" -ForegroundColor Yellow
        }
        "minor" {
            $minor++
            $patch = 0
            Write-Host "Bumping MINOR version" -ForegroundColor Yellow
        }
        "patch" {
            $patch++
            Write-Host "Bumping PATCH version" -ForegroundColor Yellow
        }
    }
    
    # Luôn tăng versionCode
    $versionCode++
    
    $newVersion = "$major.$minor.$patch+$versionCode"
    
    # Thay thế version trong file
    $newContent = $content -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $newVersion"
    
    # Ghi lại file
    Set-Content -Path $pubspecPath -Value $newContent -NoNewline
    
    Write-Host "Version updated to: $newVersion" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Review the changes in pubspec.yaml"
    Write-Host "  2. Commit the version change"
    Write-Host "  3. Build your app: flutter build apk --release"
} else {
    Write-Host "Error: Could not parse version from pubspec.yaml" -ForegroundColor Red
    exit 1
}


param (
    [Parameter(Mandatory)][string]$winEdition,
    [Parameter(Mandatory)][string]$outputISO,
    [Parameter(Mandatory)][string]$esdConvert,
    [Parameter(Mandatory)][string]$useOscdimg
)

$scriptRoot = $PSScriptRoot
$isoPath = Join-Path $scriptRoot "Win11.iso"
$debloater = Join-Path $scriptRoot 'isoDebloaterScript.ps1'
$getIsoScript = Join-Path $scriptRoot 'GetWindowsISO.ps1'

# Determine cache file based on Windows edition
if ($winEdition -like "*Windows 11*") {
    $cacheFile = Join-Path $scriptRoot ".github\links\win11_iso_link.txt"
    $getIsoParam = "-win11"
} elseif ($winEdition -like "*Windows 10*") {
    $cacheFile = Join-Path $scriptRoot ".github\links\win10_iso_link.txt"
    $getIsoParam = "-win10"
} else {
    Write-Host "[ERROR] Unknown Windows edition specified: $winEdition"
    exit 1
}

# Convert parameters to the expected format (yes/no)
function ConvertToYesNo {
    param([string]$value)
    
    $value = $value.ToLower()
    
    if ($value -eq "true") { return "yes" }
    if ($value -eq "false") { return "no" }
    if ($value -eq "yes" -or $value -eq "no") { return $value }
    
    # Default to "no" if the value is not recognized
    return "no"
}

# Function to test if ISO link is valid
function Test-IsoLink {
    param([string]$url)
    
    try {
        Write-Host "[INFO] Testing ISO link validity..."
        $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 30 -ErrorAction Stop
        return $response.StatusCode -eq 200
    } catch {
        Write-Host "[WARN] ISO link test failed: $($_.Exception.Message)"
        return $false
    }
}

# Function to get fresh ISO link
function Get-FreshIsoLink {
    param([string]$getIsoParam)
    
    Write-Host "[INFO] Getting fresh ISO link using GetWindowsISO.ps1..."
    try {
        # Capture all output from the script
        $scriptOutput = & pwsh -ExecutionPolicy Bypass -File $getIsoScript $getIsoParam -ReturnOnly 2>&1
        
        # Extract the actual URL from the output (look for https:// lines)
        $isoLink = $null
        foreach ($line in $scriptOutput) {
            $lineStr = $line.ToString().Trim()
            if ($lineStr.StartsWith("https://") -and $lineStr.Contains("software.download.prss.microsoft.com")) {
                $isoLink = $lineStr
                break
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($isoLink)) {
            Write-Host "[DEBUG] Script output was:"
            $scriptOutput | ForEach-Object { Write-Host "  $_" }
            throw "Could not extract valid ISO URL from GetWindowsISO.ps1 output"
        }
        
        Write-Host "[INFO] Extracted ISO URL: $($isoLink.Substring(0, [Math]::Min(100, $isoLink.Length)))..."
        return $isoLink
    } catch {
        Write-Host "[ERROR] Failed to get fresh ISO link: $($_.Exception.Message)"
        throw
    }
}

# Function to save ISO link to cache
function Save-IsoLink {
    param([string]$url, [string]$filePath)
    
    try {
        # Ensure directory exists
        $directory = Split-Path $filePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Save with timestamp
        $content = @"
$url
# Cached at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')
"@
        Set-Content -Path $filePath -Value $content -Encoding UTF8
        Write-Host "[INFO] ISO link cached to: $filePath"
    } catch {
        Write-Host "[WARN] Failed to cache ISO link: $($_.Exception.Message)"
    }
}

$esdConvert = ConvertToYesNo -value $esdConvert
$useOscdimg = ConvertToYesNo -value $useOscdimg

Write-Host "[INFO] Using parameters: ESDConvert=$esdConvert, useOscdimg=$useOscdimg"
Write-Host "[INFO] Windows Edition: $winEdition"
Write-Host "[INFO] Cache file: $cacheFile"

# Try to get ISO link from cache first
$isoLink = $null
if (Test-Path $cacheFile) {
    try {
        Write-Host "[INFO] Found cached ISO link, reading..."
        $cachedContent = Get-Content $cacheFile -First 1 -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($cachedContent) -and $cachedContent.StartsWith("http")) {
            Write-Host "[INFO] Testing cached ISO link..."
            if (Test-IsoLink -url $cachedContent) {
                $isoLink = $cachedContent
                Write-Host "[INFO] Cached ISO link is valid, using it"
            } else {
                Write-Host "[WARN] Cached ISO link is invalid or expired"
            }
        }
    } catch {
        Write-Host "[WARN] Failed to read cached ISO link: $($_.Exception.Message)"
    }
}

# If no valid cached link, get fresh one
if ([string]::IsNullOrWhiteSpace($isoLink)) {
    Write-Host "[INFO] Getting fresh ISO link..."
    $isoLink = Get-FreshIsoLink -getIsoParam $getIsoParam
    Save-IsoLink -url $isoLink -filePath $cacheFile
    
    # Commit the cache file back to repo (if running in GitHub Actions)
    if ($env:GITHUB_ACTIONS -eq "true") {
        try {
            Write-Host "[INFO] Attempting to commit updated cache file to repository..."
            
            # Check if we're in a git repository
            $gitStatus = git status 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARN] Not in a git repository, skipping cache commit"
            } else {
                git config --global user.name "github-actions[bot]"
                git config --global user.email "github-actions[bot]@users.noreply.github.com"
                git add $cacheFile
                
                # Check if there are changes to commit
                $gitDiff = git diff --cached --exit-code 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[INFO] No changes to commit for cache file"
                } else {
                    git commit -m "Update ISO link cache for $winEdition" -m "Auto-updated by GitHub Actions workflow"
                    git push
                    Write-Host "[INFO] Cache file committed successfully"
                }
            }
        } catch {
            Write-Host "[WARN] Failed to commit cache file: $($_.Exception.Message)"
        }
    }
}

Write-Host "[INFO] Using ISO link: $isoLink"
Write-Host "[INFO] Downloading ISO using aria2..."

# Download ISO
aria2c --max-connection-per-server=16 --split=16 --dir=$scriptRoot --out=Win11.iso $isoLink

if (-not (Test-Path $isoPath)) {
    Write-Host "[ERROR] ISO download failed!"
    exit 1
}

# Monitor job — deletes ISO if mounted
$monitorJob = Start-Job -ScriptBlock {
    param($targetISO)
    Start-Sleep -Seconds 5
    try {
        $diskImage = Get-DiskImage -ImagePath $targetISO -ErrorAction SilentlyContinue
        if ($diskImage -and $diskImage.Attached) {
            Remove-Item -Path $targetISO -Force -ErrorAction SilentlyContinue
        }
    } catch {}
} -ArgumentList $isoPath

# Run debloater script
Write-Host "[INFO] Running debloater script..."
& pwsh -NonInteractive -NoLogo -NoProfile -ExecutionPolicy Bypass -File $debloater `
    -noPrompt `
    -isoPath $isoPath `
    -winEdition $winEdition `
    -outputISO $outputISO `
    -ESDConvert $esdConvert `
    -useOscdimg $useOscdimg

# Clean up monitor job
Wait-Job $monitorJob | Out-Null
Remove-Job $monitorJob

Write-Host "[INFO] Process completed successfully!"
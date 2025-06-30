param(
    [switch]$win10,
    [switch]$win11,
    [switch]$ReturnOnly  # New parameter to return URL without display
)

# Function to make HTTP requests with error handling and Mac user agent spoofing
function Invoke-WebRequestSafe {
    param(
        [string]$Uri
    )
    
    try {
        # Mac user agent for spoofing (only safe header to add)
        $userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -UserAgent $userAgent
        return $response.Content | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to fetch data from $Uri : $_"
        exit 1
    }
}

# Check if at least one parameter is provided
if (-not $win10 -and -not $win11) {
    Write-Host "Usage: .\script.ps1 -win10 OR .\script.ps1 -win11" -ForegroundColor Red
    exit 1
}

# Optimized target OS detection
$targetOS = if ($win10) { "Windows 10" } else { "Windows 11" }
Write-Host "Fetching $targetOS download link..." -ForegroundColor Cyan

# Step 1: Get products list
Write-Host "Fetching products list..."
$productsUrl = "https://msdl.gravesoft.dev/data/products.json"
$products = Invoke-WebRequestSafe -Uri $productsUrl

# Step 2: Find the product ID for Windows 10 or 11 with heart symbol
$productId = $null
$searchPattern = "❤️.*$targetOS"

foreach ($key in $products.PSObject.Properties.Name) {
    $value = $products.$key
    if ($value -match $searchPattern) {
        $productId = $key
        Write-Host "Found $targetOS product: $value"
        break
    }
}

if (-not $productId) {
    Write-Error "Could not find $targetOS product with heart symbol"
    exit 1
}

# Step 3: Get SKU information
Write-Host "Fetching SKU information for product ID: $productId"
$skuUrl = "https://api.gravesoft.dev/msdl/skuinfo?product_id=$productId"
$skuInfo = Invoke-WebRequestSafe -Uri $skuUrl

# Step 4: Find English language SKU
$englishSkuId = $null
foreach ($sku in $skuInfo.Skus) {
    if ($sku.Language -eq "English") {
        $englishSkuId = $sku.Id
        Write-Host "Found English SKU: $($sku.Description)"
        break
    }
}

if (-not $englishSkuId) {
    Write-Error "Could not find English language SKU for $targetOS"
    exit 1
}

# Step 5: Get download link
Write-Host "Fetching download link..."
$downloadUrl = "https://api.gravesoft.dev/msdl/proxy?product_id=$productId&sku_id=$englishSkuId"
$downloadInfo = Invoke-WebRequestSafe -Uri $downloadUrl

# Step 6: Extract and display the URI with enhanced formatting
if ($downloadInfo.ProductDownloadOptions -and $downloadInfo.ProductDownloadOptions.Count -gt 0) {
    $downloadUri = $downloadInfo.ProductDownloadOptions[0].Uri
    $productName = $downloadInfo.ProductDownloadOptions[0].ProductDisplayName
    $language = $downloadInfo.ProductDownloadOptions[0].Language
    
    # If ReturnOnly is specified, just return the URL
    if ($ReturnOnly) {
        return $downloadUri
    }
    
    Write-Host "WINDOWS ISO DOWNLOAD INFORMATION"
    Write-Host "Product    : $productName"
    Write-Host "Language   : $language"
    Write-Host "Download URI: $downloadUri"
    
    # Copy to clipboard with enhanced compatibility
    try {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            $downloadUri | Set-Clipboard
        } else {
            # PowerShell 5.1 fallback
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.Clipboard]::SetText($downloadUri)
        }
    }
    catch {
        # Silent fail for clipboard
    }
    
    # Also return the URL for variable capture
    return $downloadUri
}
else {
    Write-Error "No download options found in the response"
    exit 1
}
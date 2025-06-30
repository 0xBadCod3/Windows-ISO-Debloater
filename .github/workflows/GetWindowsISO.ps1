param(
    [switch]$win10,
    [switch]$win11,
    [switch]$ReturnOnly
)

# Function to make HTTP requests
function Invoke-WebRequestSafe {
    param( [string]$Uri )
    try {
        # Mac user agent for spoofing
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
Write-Host "[INFO] Fetching $targetOS download link..."

# Step 1: Get products list
Write-Host "[INFO] Fetching products list..."
$productsUrl = "https://msdl.gravesoft.dev/data/products.json"
$products = Invoke-WebRequestSafe -Uri $productsUrl

# Step 2: Find the product ID for Windows 10 or 11 with heart symbol
$productId = $null
$searchPattern = "❤️.*$targetOS"

foreach ($key in $products.PSObject.Properties.Name) {
    $value = $products.$key
    if ($value -match $searchPattern) {
        $productId = $key
        Write-Host "[INFO] Found $targetOS product: $value"
        break
    }
}

if (-not $productId) {
    Write-Error "Could not find $targetOS product with heart symbol"
    exit 1
}

# Step 3: Get SKU information
Write-Host "[INFO] Fetching SKU information for product ID: $productId"
$skuUrl = "https://api.gravesoft.dev/msdl/skuinfo?product_id=$productId"
$skuInfo = Invoke-WebRequestSafe -Uri $skuUrl

# Step 4: Find English language SKU
$englishSkuId = $null
foreach ($sku in $skuInfo.Skus) {
    if ($sku.Language -eq "English") {
        $englishSkuId = $sku.Id
        Write-Host "[INFO] Found English SKU: $($sku.Description)"
        break
    }
}

if (-not $englishSkuId) {
    Write-Error "Could not find English language SKU for $targetOS"
    exit 1
}

# Step 5: Get download link
Write-Host "[INFO] Fetching download link..."
$downloadUrl = "https://api.gravesoft.dev/msdl/proxy?product_id=$productId&sku_id=$englishSkuId"
$downloadInfo = Invoke-WebRequestSafe -Uri $downloadUrl

# Step 6: Extract and display the URI with enhanced formatting (FIXED FOR x64)
if ($downloadInfo.ProductDownloadOptions -and $downloadInfo.ProductDownloadOptions.Count -gt 0) {
    # Function to determine architecture from URI using proper regex
    function Get-ArchitectureFromUri {
        param([string]$Uri)
        
        # Extract filename from URI
        if ($Uri -match '/([^/]+\.iso)(\?|$)') {
            $filename = $matches[1]
            
            # Check for x64 pattern
            if ($filename -match '[\-_]x64[v\.]|x64v\d') { return "x64" }
            # Check for x32 pattern 
            elseif ($filename -match '[\-_]x32[v\.]|x32v\d') { return "x32" }
            # Check for arm64 pattern (future-proofing)
            elseif ($filename -match '[\-_]arm64[v\.]|arm64v\d') { return "arm64" }
        }
        return "Unknown"
    }
    
    # Filter for x64 version
    $x64Option = $null
    
    foreach ($option in $downloadInfo.ProductDownloadOptions) {
        $arch = Get-ArchitectureFromUri -Uri $option.Uri
        
        # Prefer x64 architecture
        if ($arch -eq "x64" -and -not $x64Option) {
            $x64Option = $option
            Write-Host "[INFO] Found x64 version"
        }
    }
    
    # Select the best option (prefer x64, fallback to first available)
    $selectedOption = if ($x64Option) { $x64Option } else { $downloadInfo.ProductDownloadOptions[0] }
    
    $downloadUri = $selectedOption.Uri
    $productName = $selectedOption.ProductDisplayName
    $language = $selectedOption.Language
    $architecture = Get-ArchitectureFromUri -Uri $downloadUri
    
    # If ReturnOnly is specified, just return the URL
    if ($ReturnOnly) {
        return $downloadUri
    }
    
    Write-Host "[INFO] Product: $productName"
    Write-Host "[INFO] Language: $language"
    Write-Host "[INFO] Architecture: $architecture"
    Write-Host "[INFO] Download URI: $downloadUri"
    
    # Also return the URL for variable capture
    return $downloadUri
}
else {
    Write-Error "No download options found in the response"
    exit 1
}
# Define ExitCodes if not already defined
if (-not ([System.Management.Automation.PSTypeName]'ExitCodes').Type) {
    enum ExitCodes {
        Success = 0
        DownloadChecksumFailure = 100
        ExtractionFailure = 101
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$OutFile,
        [int]$MaxRetries = 5,
        [int]$RetryDelaySeconds = 5,
        [string]$UserAgent = "NativeHost"
    )

    $attempt = 0
    $success = $false

    while ($attempt -lt $MaxRetries -and -not $success) {
        try {
            $attempt++
            Write-Host "Attempt ${attempt}: Downloading ${Url}..." -ForegroundColor Yellow
            
            $dir = Split-Path -Path $OutFile
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UserAgent $UserAgent -ErrorAction Stop
            $success = $true
        } catch {
            Write-Warning "Attempt ${attempt} failed: $($_.Exception.Message)"
            if ($attempt -lt $MaxRetries) {
                Write-Host "Retrying in ${RetryDelaySeconds} seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $RetryDelaySeconds
            } else {
                throw "Failed to download ${Url} after ${MaxRetries} attempts."
            }
        }
    }
}

function Get-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)] [string]$ToolName,
        [Parameter(Mandatory=$True)] [string]$Url,
        [Parameter(Mandatory=$True)] [string]$DestPath,
        [Parameter(Mandatory=$True)] [string]$DownloadPath,
        [Parameter(Mandatory=$False)] [string]$Checksum = "",
        [bool]$ExtractZip = $False,
        [bool]$ZipRelocate = $False,
        [string]$ZipRelocateFilter = "",
        [bool]$ExtractInSupportRoot = $False
    )

    if (-not (Test-Path $DestPath)) {
        Write-Host "Downloading $ToolName..." -ForegroundColor Yellow

        Invoke-WithRetry -Url $Url -OutFile $DownloadPath

        if (-not [string]::IsNullOrWhiteSpace($Checksum)) {
            Write-Host "Verifying checksum for $ToolName..." -ForegroundColor Cyan
            $calculatedChecksum = (Get-FileHash -Algorithm SHA256 $DownloadPath).Hash
            if ($calculatedChecksum -ne $Checksum) {
                Remove-Item -Path $DownloadPath -ErrorAction SilentlyContinue
                Write-Error "Invalid checksum for $ToolName`nExpected: $Checksum`nActual:   $calculatedChecksum"
                exit [int][ExitCodes]::DownloadChecksumFailure
            }
        }

        if ($ExtractZip) {
            Write-Host "Extracting $ToolName..." -ForegroundColor Yellow
            
            $targetExtractionPath = if ($ExtractInSupportRoot) { $BuilderPaths.SupportRoot } else { $DestPath }
            
            if (-not (Test-Path $targetExtractionPath)) { 
                New-Item -ItemType Directory -Path $targetExtractionPath -Force | Out-Null 
            }

            try {
                Expand-Archive -Path $DownloadPath -DestinationPath $targetExtractionPath -Force
            } catch {
                # FIXED: Wrapped in curly braces to prevent variable reference errors
                Write-Error "Unable to extract ${ToolName}: $($_.Exception.Message)"
                exit [int][ExitCodes]::ExtractionFailure
            }

            if ($ZipRelocate) {
                $folders = Get-ChildItem -Path $targetExtractionPath -Filter $ZipRelocateFilter -Directory
                if ($folders) {
                    Move-Item -Path "$($folders.FullName)\*" -Destination $DestPath -Force
                    Remove-Item $folders.FullName -Recurse -Force
                }
            }
        }
        else {
            $parentDir = Split-Path -Path $DestPath
            if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
            Move-Item -Path $DownloadPath -Destination $DestPath -Force
        }
        Write-Host "$ToolName installed successfully." -ForegroundColor Green
    }
    else {
        Write-Host "$ToolName already exists at $DestPath" -ForegroundColor Green
    }
}
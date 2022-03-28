function Get-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$ToolName,
        [Parameter(Mandatory=$True)]
        [string]$Url,
        [Parameter(Mandatory=$True)]
        [string]$DestPath,
        [Parameter(Mandatory=$True)]
        [string]$DownloadPath,
        [Parameter(Mandatory=$True)]
        [string]$Checksum,
        [Parameter(Mandatory=$False)]
        [bool]$ExtractZip = $False,
        [Parameter(Mandatory=$False)]
        [bool]$ZipRelocate = $False,
        [Parameter(Mandatory=$False)]
        [string]$ZipRelocateFilter = "",
        [Parameter(Mandatory=$False)]
        [bool]$ExtractInSupportRoot = $False
    )

    if( -not (Test-Path $DestPath) )
    {
        Write-Host "Downloading $ToolName..." -ForegroundColor Yellow

        Invoke-WebRequest -Uri $Url -OutFile $DownloadPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox

        $calculatedChecksum = ( Get-FileHash -Algorithm SHA256 $DownloadPath ).Hash
        if( $calculatedChecksum -ne $Checksum )
        {
            Remove-Item -Path $DownloadPath -ErrorAction SilentlyContinue
            Write-Error "Invalid checksum for $ToolName, expected: $cmakeChecksum actual: $calculatedChecksum"

            Exit [ExitCodes]::DownloadChecksumFailure
        }

        if( $ExtractZip )
        {
            Write-Host "Extracting $ToolName" -ForegroundColor Yellow
            if( $ExtractInSupportRoot )
            {
                Expand-ZipArchive $DownloadPath $supportPathRoot
            }
            else
            {
                Expand-ZipArchive $DownloadPath $DestPath
            }

            if (!$?) {
                Write-Error "Unable to extract $ToolName"
                Exit 2
            }

            if( $ZipRelocate )
            {
                $folders = Get-ChildItem $ZipRelocateFilter -Directory
                Move-Item $folders $DestPath
            }
        }
        else
        {
            Move-Item $DownloadPath $DestPath
        }
    }
    else
    {
        Write-Host "$ToolName already exists" -ForegroundColor Green
    }
}
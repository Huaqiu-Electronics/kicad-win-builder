function Expand-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$ToolName,
        [Parameter(Mandatory=$True)]
        [string]$SourcePath,
        [Parameter(Mandatory=$True)]
        [string]$DestPath,
        [Parameter(Mandatory=$False)]
        [bool]$ZipRelocate = $False,
        [Parameter(Mandatory=$False)]
        [string]$ZipRelocateFilter = "",
        [Parameter(Mandatory=$False)]
        [bool]$ExtractInSupportRoot = $False
    )

    if( -not (Test-Path $DestPath) ) {
        Write-Host "Extracting $ToolName" -ForegroundColor Yellow
        if( $ExtractInSupportRoot ) {
            Expand-ZipArchive $SourcePath $BuilderPaths.SupportRoot
        }
        else  {
            Expand-ZipArchive $SourcePath $DestPath
        }

        if (!$?) {
            Write-Error "Unable to extract $ToolName"
            Exit 2
        }

        if( $ZipRelocate )  {
            $folders = Get-ChildItem $ZipRelocateFilter -Directory
            Move-Item $folders $DestPath
        }
    }
    else  {
        Write-Host "$ToolName already exists" -ForegroundColor Green
    }
}
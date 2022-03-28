function Expand-ZipArchive([string] $zip, [string] $dest) {
    Write-Host "Extracting $zip to $dest"
    Try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
    }
    Catch {
        Write-Error "Error trying to extract $zip"
        Exit [ExitCodes]::DownloadExtractFailure
    }
}
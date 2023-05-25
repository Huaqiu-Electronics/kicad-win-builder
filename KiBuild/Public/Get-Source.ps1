function Get-Source {    
    <#
    .SYNOPSIS
        Fetches a given source code by url
    .DESCRIPTION
        The cmdlet takes a given source path (currently only git supported)
        and extracts it to a destination. Additionally modifiers such as tags and branch
        are supported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$url,
        [Parameter(Mandatory=$True)]
        [string]$dest,
        [Parameter(Mandatory=$True)]
        [SourceType]$sourceType,
        [Parameter(Mandatory=$False)]
        [bool]$latest = $False,
        [Parameter(Mandatory=$False)]
        [string]$ref = ""
    )

    if(![System.IO.Directory]::Exists($dest)) {
        if($sourceType -eq [SourceType]::git) {
            & git clone "$url" "$dest"

            if ($LastExitCode -ne 0) {
                Write-Error "Error cloning kicad repo"
                Exit [ExitCodes]::GitCloneFailure
            }
        }
        elseif($sourceType -eq [SourceType]::tar) {

        }
    }

    if( ($sourceType -eq [SourceType]::git) -and $ref ) {

        $gitCheckTag = ""
        $gitCheckBranch = ""

        if( $ref ) {
            if( $ref.StartsWith("branch/") ) {
                $gitCheckBranch = $ref.Replace("branch/", "")
            }
            elseif ($ref.StartsWith("tag/") ) {
                $gitCheckTag = $ref.Replace("tag/", "")
            }
        }

        git -C "$dest" fetch --all --tags --force
        if ($LastExitCode -ne 0) {
            Write-Error "Error git clean"
            Exit [ExitCodes]::GitFetch
        }

        git -C "$dest" reset --hard
        if ($LastExitCode -ne 0) {
            Write-Error "Error git reset"
            Exit [ExitCodes]::GitResetFailure
        }
        
        git -C "$dest" clean -f
        if ($LastExitCode -ne 0) {
            Write-Error "Error git clean"
            Exit [ExitCodes]::GitCleanFailure
        }

        if( $gitCheckTag -ne "" ) {
            git -C "$dest" checkout tags/$gitCheckTag
        } elseif ( $gitCheckBranch -ne "" ) {
            git -C "$dest" checkout origin/$gitCheckBranch
        }

        if ($LastExitCode -ne 0) {
            Write-Error "Error git checkout ref"
            Exit [ExitCodes]::GitCheckoutTag
        }
    }
}
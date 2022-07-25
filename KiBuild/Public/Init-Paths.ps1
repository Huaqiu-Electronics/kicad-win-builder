function Init-Paths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Root
    )
    
    $BuilderPaths.SupportRoot = Join-Path -Path $Root -ChildPath "/.support/"
    $BuilderPaths.DownloadsRoot = Join-Path -Path $Root -ChildPath "/.downloads/"
    $BuilderPaths.BuildRoot = Join-Path -Path $Root -ChildPath "/.build/"
    $BuilderPaths.OutRoot = Join-Path -Path $Root -ChildPath "/.out/"
    $BuilderPaths.KiBuildEnv = Join-Path -Path $Root -ChildPath "/.kibuild/"
    
    if( -not (Test-Path $BuilderPaths.DownloadsRoot) )
    {
        New-Item $BuilderPaths.DownloadsRoot -ItemType "directory"
    }

    if( -not (Test-Path $BuilderPaths.SupportRoot ) )
    {
        New-Item $BuilderPaths.SupportRoot -ItemType "directory"
    }

    if( -not (Test-Path $BuilderPaths.BuildRoot ) )
    {
        New-Item $BuilderPaths.BuildRoot -ItemType "directory"
    }

    if( -not (Test-Path $BuilderPaths.OutRoot ) )
    {
        New-Item $BuilderPaths.OutRoot -ItemType "directory"
    }
    
    if( -not (Test-Path $BuilderPaths.KiBuildEnv ) )
    {
        New-Item $BuilderPaths.KiBuildEnv -ItemType "directory"
    }
}
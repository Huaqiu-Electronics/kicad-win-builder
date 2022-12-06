#  Copyright (C) 2022 Mark Roszko <mark.roszko@gmail.com>
#  Copyright (C) 2022 KiCad Developers
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#

param(
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="publish_symstore")]
    [Switch]$PublishSymStore,
    
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="publish_sentry")]
    [Switch]$PublishSentry,

    [Parameter(Mandatory=$True, ParameterSetName="publish_symstore")]
    [Parameter(Mandatory=$True, ParameterSetName="publish_sentry")]
	[ValidateScript({Test-Path $_})]
    [string]$SourcePath,

    [Parameter(Mandatory=$True, ParameterSetName="publish_symstore")]
	[ValidateScript({Test-Path $_})]
    [string]$SymbolStore,
    
    [Parameter(Mandatory=$False, ParameterSetName="publish_symstore")]
    [string]$SymbolStoreProduct = "kicad",
    
    [Parameter(Mandatory=$False, ParameterSetName="publish_symstore")]
    [Switch]$CleanOldSymbols,
    
    [Parameter(Mandatory=$False, ParameterSetName="publish_sentry")]
    [string]$SentryOrg = "kicad",
    
    [Parameter(Mandatory=$False, ParameterSetName="publish_sentry")]
    [string]$SentryProject = "kicad"
)

Import-Module ./KiBuild -Force

Init-Paths $PSScriptRoot
$BuilderPaths = Get-BuilderPaths

$symbolTemp = Join-Path -Path $PSScriptRoot -ChildPath "/.build/symbols-temp/"

$7zaFolderName = "7z2201-extra"

if( -not (Test-Path alias:vswhere ) ) {
    $tmp = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "vswhere.exe"
    Set-Alias vswhere $tmp -Option AllScope -Scope Global
}

if( -not (Test-Path alias:sentry-cli ) ) {
    $tmp = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "sentry-cli.exe"
    Set-Alias sentry-cli $tmp -Option AllScope -Scope Global
}

Set-MSVCEnvironment

if( -not (Test-Path alias:7za ) ) {
    $tmp = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "$7zaFolderName/7za.exe"
    Set-Alias 7za $tmp -Option AllScope -Scope Global
}

if( -not (Test-Path alias:symstore) ) {
    $tmp = Join-Path -Path $env:WindowsSdkDir -ChildPath "\Debuggers\x64\symstore.exe"
    Set-Alias symstore $tmp -Option AllScope -Scope Global
}

if( -not (Test-Path alias:agestore) ) {
    $tmp = Join-Path -Path $env:WindowsSdkDir -ChildPath "\Debuggers\x64\agestore.exe"
    Set-Alias agestore $tmp -Option AllScope -Scope Global
}



function script:Step-ExtractSymbolZip {
    param (
        [string[]]$zipPath
    )

    Write-Host "Deleting symbol-temp" -ForegroundColor Yellow
    Remove-Item $symbolTemp -Recurse -ErrorAction SilentlyContinue
    
    Write-Host "Extracting $zipPath" -ForegroundColor Yellow
    7za e $zipPath -o"$symbolTemp" * -r
}

function script:Step-SymStore {
    param (
        [string[]]$path
    )

    $extn = [IO.Path]::GetExtension($path)
    if ($extn -eq ".zip" )
    {
        Step-ExtractSymbolZip $path
    }
    
    Write-Host "Invoking symstore" -ForegroundColor Yellow
    symstore add /r /f $symbolTemp /t $SymbolStoreProduct /s $SymbolStore /compress

    Write-Host "Deleting symbol-temp" -ForegroundColor Yellow
  #  Remove-Item $symbolTemp -Recurse -ErrorAction SilentlyContinue
}

function script:Step-SentryStore {
    param (
        [string[]]$path
    )

    # Note, it is expected the user has SENTRY_AUTH_TOKEN defined
    # with the environment variable with the token

    $extn = [IO.Path]::GetExtension($path)
    if ($extn -eq ".zip" )
    {
        Step-ExtractSymbolZip $path
    }
    
    Write-Host "Invoking sentry-cli" -ForegroundColor Yellow
    sentry-cli upload-dif -o $SentryOrg -p $SentryProject $symbolTemp

    Write-Host "Deleting symbol-temp" -ForegroundColor Yellow
    Remove-Item $symbolTemp -Recurse -ErrorAction SilentlyContinue
}

if( $PublishSymStore ) {
    if( (Get-Item $SourcePath) -is [System.IO.DirectoryInfo] ) {
        Write-Host "Provided path is a directory, scanning..." -ForegroundColor Yellow

        $files = Get-ChildItem -Path $SourcePath -Filter *.zip
        foreach ($file in $files) {
            Step-SymStore $file.FullName
        }
        
    } else {
        Step-SymStore $SourcePath
    }

    if( $CleanOldSymbols )
    {
        Write-Host "Cleaning old symbols in store" -ForegroundColor Yellow
        agestore $SymbolStore -y -s -days=30
    }
}

if( $PublishSentry ) {
    if( (Get-Item $SourcePath) -is [System.IO.DirectoryInfo] ) {
        Write-Host "Provided path is a directory, scanning..." -ForegroundColor Yellow

        $files = Get-ChildItem -Path $SourcePath -Filter *.zip
        foreach ($file in $files) {
            Step-SentryStore $file.FullName
        }

        $commitHashPath = Join-Path -Path $SourcePath -ChildPath "commit-hash"
        $commitHash = Get-Content -Path $commitHashPath -Encoding ascii

        Write-Host "Setting release commit in Sentry" -ForegroundColor Yellow
        sentry-cli releases -o $SentryOrg -p $SentryProject set-commits --commit "KiCad / KiCad Source Code / kicad@$commitHash" $commitHash
    } else {
        Step-SentryStore $SourcePath
    }
}
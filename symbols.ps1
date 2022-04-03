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
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="publish")]
    [Switch]$Publish,

    [Parameter(Mandatory=$True, ParameterSetName="publish")]
	[ValidateScript({Test-Path $_})]
    [string]$SourceZipPath,

    [Parameter(Mandatory=$True, ParameterSetName="publish")]
	[ValidateScript({Test-Path $_})]
    [string]$SymbolStore,
    
    [Parameter(Mandatory=$False, ParameterSetName="publish")]
    [string]$SymbolStoreProduct = "kicad",
    
    [Parameter(Mandatory=$False, ParameterSetName="publish")]
    [Switch]$CleanOldSymbols
)

Import-Module ./KiBuild -Force

$supportPathRoot = Join-Path -Path $PSScriptRoot -ChildPath "/.support/"
$symbolTemp = Join-Path -Path $PSScriptRoot -ChildPath "/.build/symbols-temp/"

$7zaFolderName = "7z2102-extra"

if( -not (Test-Path alias:vswhere ) ) {
    $tmp = Join-Path -Path $supportPathRoot -ChildPath "vswhere.exe"
    Set-Alias vswhere $tmp -Option AllScope -Scope Global
}

Set-MSVCEnvironment

if( -not (Test-Path alias:7za ) ) {
    $tmp = Join-Path -Path $supportPathRoot -ChildPath "$7zaFolderName/7za.exe"
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


function script:Step-SymbolProcess {
    param (
        [string[]]$zipPath
    )

    Write-Host "Deleting symbol-temp" -ForegroundColor Yellow
    Remove-Item $symbolTemp -Recurse -ErrorAction SilentlyContinue
    
    Write-Host "Extracting $zipPath" -ForegroundColor Yellow
    7za e $zipPath -o"$symbolTemp" *.pdb -r
    
    Write-Host "Invoking symstore" -ForegroundColor Yellow
    symstore add /r /f $symbolTemp /t $SymbolStoreProduct /s $SymbolStore /compress

    Write-Host "Deleting symbol-temp" -ForegroundColor Yellow
    Remove-Item $symbolTemp -Recurse -ErrorAction SilentlyContinue
}

if( $Publish ) {
    if( (Get-Item $SourceZipPath) -is [System.IO.DirectoryInfo] ) {
        Write-Host "Provided path is a directory, scanning..." -ForegroundColor Yellow

        $files = Get-ChildItem -Path $SourceZipPath -Filter *.zip
        foreach ($file in $files) {
            Step-SymbolProcess $file.FullName
        }
        
    } else {
        Step-SymbolProcess $SourceZipPath
    }

    if( $CleanOldSymbols )
    {
        Write-Host "Cleaning old symbols in store" -ForegroundColor Yellow
        agestore $SymbolStore -y -days=30
    }
}
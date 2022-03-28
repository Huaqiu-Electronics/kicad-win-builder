function New-TileIcons {
    <#
    .SYNOPSIS
        Converts a given SVG to all possible tile icons for Windows MSIX packaging
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [string]$OutBase
    )

    New-TileIcon -Svg $Svg -OutBase $OutBase -Width 44 -Height 44
    New-TileIcon -Svg $Svg -OutBase $OutBase -Width 71 -Height 71 -Padding $True
    New-TileIcon -Svg $Svg -OutBase $OutBase -Width 150 -Height 150 -Padding $True
    New-TileIcon -Svg $Svg -OutBase $OutBase -Width 310 -Height 310 -Padding $True
    New-TileIcon -Svg $Svg -OutBase $OutBase -Width 310 -Height 150 -Padding $True
}
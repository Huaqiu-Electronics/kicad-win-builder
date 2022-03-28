function New-TileIcon {
    <#
    .SYNOPSIS
        Converts a given SVG to the bundle tile icons for Windows MSIX packaging
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [int]$Width,
        [Parameter(Mandatory=$True)]
        [int]$Height,
        [Parameter(Mandatory=$True)]
        [string]$OutBase,
        [Parameter(Mandatory=$False)]
        [bool]$Padding = $False
    )


    New-TileIconSub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 100
    New-TileIconSub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 125
    New-TileIconSub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 150
    New-TileIconSub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 200
    New-TileIconSub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 400
}
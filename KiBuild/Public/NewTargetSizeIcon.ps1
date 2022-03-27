function New-TargetSizeIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [int]$Size,
        [Parameter(Mandatory=$True)]
        [string]$OutBase
    )

    $out = "${OutBase}.targetsize-${Size}.png"
    Convert-Svg -Svg $svg -Width $Size -Height $Size -Out $out

    $out = "${OutBase}.targetsize-${Size}_altform-unplated.png"
    Convert-Svg -Svg $svg -Width $Size -Height $Size -Out $out
}
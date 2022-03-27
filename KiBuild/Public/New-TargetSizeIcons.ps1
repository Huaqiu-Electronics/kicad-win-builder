# Target size are specific 16,24,32,48,256
function New-TargetSizeIcons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [string]$OutBase
    )

    New-TargetSizeIcon -Svg $Svg -OutBase $OutBase -Size 16
    New-TargetSizeIcon -Svg $Svg -OutBase $OutBase -Size 24
    New-TargetSizeIcon -Svg $Svg -OutBase $OutBase -Size 32
    New-TargetSizeIcon -Svg $Svg -OutBase $OutBase -Size 48
    New-TargetSizeIcon -Svg $Svg -OutBase $OutBase -Size 256
}
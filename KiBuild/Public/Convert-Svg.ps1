function Convert-Svg {
    <#
    .SYNOPSIS
        Converts a given SVG to png using inkscape
    .DESCRIPTION
        The cmdlet takes a input svg path and converts it to an output png file.
        inkscape is used as the svg to png processor.
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
        [string]$Out
    )

    Write-Host "Converting $Svg to $Out, w: $Width, h: $Height"

    inkscape --export-area-snap --export-type=png "$Svg" --export-filename "$Out" -w $Width -h $Height 2>$null

    if( $LastExitCode -ne 0 ) {
        Write-Error "Error generating png from svg"
        Exit [ExitCodes]::InkscapeSvgConversion
    }
}
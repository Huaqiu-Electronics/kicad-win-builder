function Convert-Svg {
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

    if( $LastExitCode -ne 0 )
    {
        Write-Error "Error generating png from svg"
        Exit [ExitCodes]::InkscapeSvgConversion
    }
}
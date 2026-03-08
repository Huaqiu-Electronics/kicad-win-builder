

# $imageHelper = @"
# using System;
# using System.Drawing;
# using System.Drawing.Imaging;

# public class ImageHelper
# {
#     public static void TilizeIcon(string sourcePath, int finalWidth, int finalHeight, string finalPath)
#     {
#         using (var finalImage = new Bitmap(finalWidth, finalHeight))
#         {
#             using (var source = new Bitmap(sourcePath))
#             {
#                 if(source.Width > finalWidth)
#                 {
#                     throw new ArgumentOutOfRangeException("Source width is larger than the final width");
#                 }

#                 if (source.Height > finalHeight)
#                 {
#                     throw new ArgumentOutOfRangeException("Source height is larger than the final height");
#                 }

#                 using (Graphics g = Graphics.FromImage(finalImage))
#                 {
#                     g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
#                     g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
#                     g.DrawImage(source, (finalWidth-source.Width)/2, (finalHeight-source.Height)/2, source.Width, source.Height);
#                 }
#             }

#             finalImage.Save(finalPath, ImageFormat.Png);
#         }
#     }
# }
# "@

# $assemblies = ("System.Drawing", "System.Drawing.Primitives", "System.Runtime")
# Add-Type -ReferencedAssemblies $assemblies -TypeDefinition $imageHelper -Language CSharp -IgnoreWarnings
# function New-TileIconSub {
#     <#
#     .SYNOPSIS
#         Sub-helper for generating msix bundle icons
#     #>
#     [CmdletBinding()]
#     param(
#         [Parameter(Mandatory=$True)]
#         [string]$Svg,
#         [Parameter(Mandatory=$True)]
#         [int]$Width,
#         [Parameter(Mandatory=$True)]
#         [int]$Height,
#         [Parameter(Mandatory=$True)]
#         [string]$OutBase,
#         [Parameter(Mandatory=$True)]
#         [int]$Scale,
#         [Parameter(Mandatory=$False)]
#         [bool]$Padding = $False
#     )

#     $shape = 'Square';
#     if( $Width -ne $Height )
#     {
#         $shape = 'Wide';
#     }

#     $OutBase = "${OutBase}-${shape}${Width}x${Height}Logo";

#     $out = "${OutBase}.scale-${Scale}.png"
#     $finalWidth = $Width * ($Scale/100.0)
#     $finalHeight = $Height* ($Scale/100.0)
#     if( $Padding )
#     {
#         $iconWidth = $finalWidth*0.66
#         $iconHeight = $finalHeight*0.50
#         $iconDim = [math]::Min($iconHeight,$iconWidth)
#         $iconDim = [math]::Round($iconDim, 0)

#         Convert-Svg -Svg $svg -Width $iconDim -Height $iconDim -Out $out
#         [ImageHelper]::TilizeIcon($out, $finalWidth, $finalHeight, $out)
#     }
#     else {
#         Convert-Svg -Svg $svg -Width $finalHeight -Height $finalHeight -Out $out
#         if( $finalWidth -eq 44 )
#         {
#             New-TargetSizeIcons -Svg $f.FullName -OutBase $OutBase
#         }
#     }
# }
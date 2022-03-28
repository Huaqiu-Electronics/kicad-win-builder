function Get-AbsolutePath($relativePath) {
  $path = Resolve-Path -Path $relativePath | Select-Object -ExpandProperty Path

  return $path
}
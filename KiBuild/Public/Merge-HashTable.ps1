function Merge-HashTable {
    <#
    .SYNOPSIS
        Merges two separate hash tables by overwrite of one with the other
    .DESCRIPTION
        The cmdlet takes two hash tables and merges them. Any keys that exist
        in both the Default and Uppend hash tables result in the Default key
        value being dropped and the Uppend's key value replacing it. Keys that only
        exist in one hashtable end up as-is in the final result.
    #>
    param(
        [hashtable] $Default,
        [hashtable] $Uppend
    )

    # Clone for idempotence
    $defaultClone = $Default.Clone();

    # Remove keys that exist in both uppend and default from default
    foreach ($key in $Uppend.Keys) {
        if ($defaultClone.ContainsKey($key)) {
            $defaultClone.Remove($key);
        }
    }

    # Union both sets
    return $defaultClone + $Uppend;
}
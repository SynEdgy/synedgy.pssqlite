function Copy-PSSqliteDefinition
{
    <#
    .SYNOPSIS
    Copies configuration collections without expanding deployment variables.
    .DESCRIPTION
    Uses case-insensitive dictionaries and preserves scalar values and arrays.
    .PARAMETER Value
    The configuration value to copy.
    .EXAMPLE
    Copy-PSSqliteDefinition -Value $definition
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([AllowNull()][object] $Value)

    if ($Value -is [System.Collections.IDictionary])
    {
        $copy = [ordered]@{}

        foreach ($key in $Value.Keys)
        {
            $copy[$key] = Copy-PSSqliteDefinition -Value $Value[$key]
        }

        return ,$copy
    }

    if ($Value -is [System.Collections.IList])
    {
        $copy = @(
            foreach ($item in $Value)
            {
                Copy-PSSqliteDefinition -Value $item
            }
        )
        return ,$copy
    }

    return ,$Value
}

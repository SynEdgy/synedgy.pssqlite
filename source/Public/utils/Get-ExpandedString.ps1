function Get-ExpandedString
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $String
    )

    return $ExecutionContext.InvokeCommand.ExpandString($String)
}

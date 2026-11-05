function Get-PSSqliteConfigurationIssue
{
    <#
    .SYNOPSIS
    Checks configuration structure and existing model invariants.
    .DESCRIPTION
    Does not expand deployment variables, open databases or execute SQL.
    Constructors receive a copy because they attach names to nested mappings.
    .PARAMETER Definition
    The complete unexpanded configuration definition.
    .PARAMETER ValidatedDefinition
    Receives a validated copy containing only recognised properties.
    .EXAMPLE
    Get-PSSqliteConfigurationIssue -Definition $definition
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][object] $Definition,
        [ref] $ValidatedDefinition
    )

    $copy = $null
    $issues = @(Get-PSSqliteDefinitionIssue -Value $Definition -CleanValue ([ref]$copy))
    if ($issues.Count -gt 0)
    {
        $issues
        return
    }

    if ($ValidatedDefinition) { $ValidatedDefinition.Value = $copy }

    $schemaDefinition = Copy-PSSqliteDefinition -Value $copy['Schema']
    try
    {
        $schema = [SqliteDBSchema]::new($schemaDefinition)
        $null = $schema.GetSchemaSDL()
    }
    catch [System.ArgumentException], [System.Management.Automation.RuntimeException]
    {
        [pscustomobject]@{ Path = '$.Schema'; Code = 'InvalidSchema'; Message = $_.Exception.Message }
    }
}

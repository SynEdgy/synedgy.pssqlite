function Test-PSSqliteConfiguration
{
    <#
    .SYNOPSIS
    Validates a complete PSSqlite YAML configuration without accessing a database.
    .DESCRIPTION
    Checks unexpanded structure and model invariants on PowerShell 5.1 and 7,
    without extra assemblies. This does not interpret JSON Schema or validate SQL.
    Invalid definitions return false and emit errors; Detailed returns diagnostics
    instead. File access and YAML parsing failures remain terminating errors.
    .PARAMETER Path
    Path to a PSSqlite YAML configuration file.
    .PARAMETER Definition
    A parsed, unexpanded configuration dictionary.
    .PARAMETER Detailed
    Returns Path, Code and Message diagnostics instead of a Boolean.
    A valid definition produces no diagnostics.
    .EXAMPLE
    Test-PSSqliteConfiguration -Path '.\config\Example.PSSqliteConfig.yml'
    .EXAMPLE
    Test-PSSqliteConfiguration -Definition $definition -Detailed
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([bool], [pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Definition')]
        [AllowNull()]
        [object] $Definition,

        [switch] $Detailed
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path')
    {
        $resolvedPath = Get-PSSqliteAbsolutePath -Path $Path
        $Definition = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop) -Ordered -ErrorAction Stop
    }

    $issues = @(Get-PSSqliteConfigurationIssue -Definition $Definition)
    if ($Detailed)
    {
        $issues
        return
    }

    foreach ($issue in $issues)
    {
        $exception = [ArgumentException]::new(('{0}: {1}' -f $issue.Path, $issue.Message))
        $record = [System.Management.Automation.ErrorRecord]::new(
            $exception, $issue.Code, [System.Management.Automation.ErrorCategory]::InvalidData, $issue.Path
        )
        $PSCmdlet.WriteError($record)
    }

    return ($issues.Count -eq 0)
}

function Compare-PSSqliteDBVersion
{
    <#
    .SYNOPSIS
    Compares the configured schema version with database metadata.
    .PARAMETER DatabaseConfig
    Database configuration.
    .PARAMETER ExpectedVersion
    Expected schema version; defaults to the configuration version.
    .PARAMETER SqliteConnection
    Optional caller-owned open connection.
    .PARAMETER SqliteTransaction
    Optional caller-owned transaction on that connection.
    .EXAMPLE
    Compare-PSSqliteDBVersion -DatabaseConfig $config
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        # Path to the database configuration file
        [SqliteDBConfig]
        $DatabaseConfig,

        [Parameter()]
        [string]
        $ExpectedVersion = $DatabaseConfig.version,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteConnection]
        $SqliteConnection,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteTransaction]
        $SqliteTransaction
    )

    $result = [ordered]@{
        'CurrentVersion' = $null
        'ExpectedVersion' = $ExpectedVersion
        'IsDeployed' = $false
        'direction' = '!='
        'Reasons' = @()
        PSTypeName = 'synedgy.PSSqlite.DBVersionComparisonResult'
    }

    $ownsConnection = -not $SqliteConnection
    if ($SqliteTransaction -and
        (-not $SqliteConnection -or $SqliteTransaction.Connection -ne $SqliteConnection))
    {
        throw [ArgumentException]::new('SqliteTransaction must belong to the supplied SqliteConnection.')
    }

    if ($ownsConnection -and -not $DatabaseConfig.databaseExists())
    {
        Write-Verbose -Message 'Database does not exist. Returning default comparison result.'
        return [PSCustomObject]$result
    }

    try
    {
        if ($ownsConnection)
        {
            $SqliteConnection = New-PSSqliteConnection -ConnectionString $DatabaseConfig.ConnectionString
        }

        $metadata = Get-PSSqliteDBMetadata -SqliteConnection $SqliteConnection -SqliteTransaction $SqliteTransaction -MetadataKey 'version' -KeepAlive -ErrorAction Stop
    }
    catch
    {
        Write-Error -Message ('Failed to retrieve metadata from the database: {0}' -f $_.Exception.Message)
        $result['Reasons'] += ('Failed to retrieve metadata from the database: {0}' -f $_.Exception.Message)
        return [PSCustomObject]$result
    }
    finally
    {
        if ($ownsConnection -and $SqliteConnection)
        {
            Write-Verbose -Message 'Closing the database connection.'
            $sqliteConnection.Close()
            $sqliteConnection.Dispose()
            Write-Verbose -Message 'Database connection closed.'
        }
    }

    if ($null -eq $metadata)
    {
        Write-Verbose -Message 'Metadata table not found.'
        $result['Reasons'] += 'Metadata table not found.'
    }
    elseif ([string]::IsNullOrEmpty($metadata['version']))
    {
        Write-Verbose -Message 'Database version is not set in the metadata.'
        $result['Reasons'] += 'Database version is not set in the metadata.'
    }
    elseif ([string]::IsNullOrEmpty($ExpectedVersion))
    {
        Write-Verbose -Message 'Expected version is not set.'
        $result['Reasons'] += 'Expected version is not set.'
        $result['ExpectedVersion'] = $null
        $result['CurrentVersion'] = $metadata['version']
        $result['direction'] = '>'
        $result['IsDeployed'] = $true
    }
    else
    {
        $version = $metadata['version']
        Write-Verbose -Message ('Current database schema version: {0}' -f $version)
        $result['CurrentVersion'] = $version
        $result['IsDeployed'] = $true


        if ($version -eq $ExpectedVersion)
        {
            Write-Verbose -Message ('Database version matches expected version (Core): {0}' -f $ExpectedVersion)
            $result['Reasons'] += ('Database version matches expected version: {0}' -f $ExpectedVersion)
            $result['direction'] = '=='
        }
        else
        {
            Write-Verbose -Message ('Database version does not match expected version: {0} -ne {1}' -f $version, $ExpectedVersion)
            $result['Reasons'] += ('Database version does not match expected version: {0} -ne {1}' -f $version, $ExpectedVersion)

            if ($version -match '^\d+$' -and $ExpectedVersion -match '^\d+$')
            {
                if ([long]$version -lt [long]$ExpectedVersion) { $result['direction'] = '<' }
                else { $result['direction'] = '>' }
            }
            elseif ($PSVersionTable.PSEdition -eq 'Core')
            {
                # [semver] is available in PowerShell Core, but not in Windows PowerShell
                Write-Verbose -Message 'Comparing versions as semver (PowerShell Core).'
                $semverDBVersion = $version -as 'semver'
                $semverExpectedVersion = $ExpectedVersion -as 'semver'

                if ($semverDBVersion -lt $semverExpectedVersion)
                {
                    Write-Verbose -Message ('Database version is lower than expected version (Core): {0} < {1}' -f $semverDBVersion, $semverExpectedVersion)
                    $result['Reasons'] += ('Database version is lower than expected version (Core): {0} < {1}' -f $semverDBVersion, $semverExpectedVersion)
                    $result['direction'] = '<'
                }
                elseif ($semverDBVersion -gt $semverExpectedVersion)
                {
                    Write-Verbose -Message ('Database version is higher than expected version (Core): {0} > {1}' -f $semverDBVersion, $semverExpectedVersion)
                    $result['Reasons'] += ('Database version is higher than expected version (Core): {0} > {1}' -f $semverDBVersion, $semverExpectedVersion)
                    $result['direction'] = '>'
                }
            }
            else
            {
                # In Windows PowerShell, we cannot use [semver], so we compare as [version]
                # [version] does not support tags (-preview0001, -alpha, etc.), so we compare just the numeric part
                # but if the version is an Int, we can't use [version] at all, so we need to handle that case
                if ($null -ne ($version -as [int]) -and $null -eq ($version -as [version]))
                {
                    Write-Verbose -Message 'Database version is an integer. Comparing as integers (Windows PowerShell).'
                    [int]$versionObj = $version
                    [int]$expectedVersionObj = $ExpectedVersion
                    if ($versionObj -eq $expectedVersionObj)
                    {
                        # in case of an integer, we should never hit this case, but let's keep it for completeness
                        Write-Verbose -Message ('Database version matches expected version (Windows PowerShell): {0} == {1}' -f $versionObj, $expectedVersionObj)
                        $result['Reasons'] += ('Database version matches expected version (Windows PowerShell): {0} == {1}' -f $versionObj, $expectedVersionObj)
                        $result['direction'] = '=='
                    }
                    elseif ($versionObj -lt $expectedVersionObj)
                    {
                        Write-Verbose -Message ('Database version is lower than expected version (Windows PowerShell): {0} < {1}' -f $versionObj, $expectedVersionObj)
                        $result['Reasons'] += ('Database version is lower than expected version (Windows PowerShell): {0} < {1}' -f $versionObj, $expectedVersionObj)
                        $result['direction'] = '<'
                    }
                    elseif ($versionObj -gt $expectedVersionObj)
                    {
                        Write-Verbose -Message ('Database version is higher than expected version (Windows PowerShell): {0} > {1}' -f $versionObj, $expectedVersionObj)
                        $result['Reasons'] += ('Database version is higher than expected version (Windows PowerShell): {0} > {1}' -f $versionObj, $expectedVersionObj)
                        $result['direction'] = '>'
                    }
                    else
                    {
                        throw "Unexpected comparison result for integer version: {0} vs {1}" -f $version, $expectedVersion
                    }
                }

                Write-Verbose -Message 'Comparing versions as [version] (Windows PowerShell).'
                $versionNoTag = $version -replace '-.*', ''
                $expectedVersionNoTag = $ExpectedVersion -replace '-.*', ''
                [version]$versionObj = $versionNoTag
                [version]$expectedVersionObj = $expectedVersionNoTag
                if ($versionObj -lt $expectedVersionObj)
                {
                    Write-Verbose -Message ('Database version is lower than expected version (Windows PowerShell): {0} < {1}' -f $versionObj, $expectedVersionObj)
                    $result['Reasons'] += ('Database version is lower than expected version (Windows PowerShell): {0} < {1}' -f $versionObj, $expectedVersionObj)
                    $result['direction'] = '<'
                }
                elseif ($versionObj -gt $expectedVersionObj)
                {
                    Write-Verbose -Message ('Database version is higher than expected version (Windows PowerShell): {0} > {1}' -f $versionObj, $expectedVersionObj)
                    $result['Reasons'] += ('Database version is higher than expected version (Windows PowerShell): {0} > {1}' -f $versionObj, $expectedVersionObj)
                    $result['direction'] = '>'
                }
                elseif ($versionObj -eq $expectedVersionObj)
                {
                    Write-Verbose -Message ('Database version matches expected version (Windows PowerShell): {0} == {1}' -f $versionObj, $expectedVersionObj)
                    $result['Reasons'] += ('Database version matches expected version (Windows PowerShell): {0} == {1}' -f $versionObj, $expectedVersionObj)
                    $result['direction'] = '=='
                }
                else
                {
                    throw "Unexpected comparison result for [version]: {0} vs {1}" -f $version, $expectedVersion
                }
            }
        }
    }

    return [PSCustomObject]$result
}

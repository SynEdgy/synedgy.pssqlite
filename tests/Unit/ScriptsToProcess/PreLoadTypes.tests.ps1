BeforeAll {
    $script:moduleName = 'synedgy.PSSqlite'
}

Describe 'PreLoadTypes' {
    It 'Should reuse an already loaded native SQLite library' {
        $module = Import-Module -Name $script:moduleName -Force -ErrorAction Stop -PassThru |
            Where-Object -Property Name -EQ $script:moduleName |
            Select-Object -First 1
        $preloadScriptPath = Join-Path -Path $module.ModuleBase -ChildPath 'ScriptsToProcess\PreLoadTypes.ps1'
        $originalVerbosePreference = $VerbosePreference

        try
        {
            $VerbosePreference = 'Continue'
            $verboseOutput = & $preloadScriptPath 4>&1
        }
        finally
        {
            $VerbosePreference = $originalVerbosePreference
        }

        $verboseText = $verboseOutput | Out-String
        $verboseText | Should -Match 'Native SQLite library already loaded in the current process'
        $verboseText | Should -Not -Match 'Loading native SQLite library'
    }
}

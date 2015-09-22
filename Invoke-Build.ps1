[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $OutputDirectory
)

function Main
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $OutputDirectory
    )

    $dependenciesPath = Join-Path $PSScriptRoot Dependencies
    $resourcesPath    = Join-Path $PSScriptRoot DSC_Resources

    $env:PSModulePath = "$dependenciesPath;$resourcesPath;$pshome\Modules"

    try
    {
        Import-Module Pester -ErrorAction Stop
        Import-Module cDscResourceDesigner -ErrorAction Stop

        RunUnitTests -Path $resourcesPath
        TestDscResources -Path $resourcesPath
        CompileTestMOFs

        $moduleDest = Join-Path $OutputDirectory Modules
        if (-not (Test-Path -LiteralPath $moduleDest -PathType Container))
        {
            $null = New-Item -Path $moduleDest -ItemType Directory -ErrorAction Stop
        }

        DeployResourceModules -Source $resourcesPath -Destination $moduleDest

        $configurationModule = Join-Path $dependenciesPath DemoConfiguration
        $configTarget = Join-Path $OutputDirectory DemoConfiguration

        if (Test-Path -LiteralPath $configTarget)
        {
            Remove-Item -LiteralPath $configTarget -Force -Recurse -ErrorAction Stop
        }

        Copy-Item -LiteralPath $configurationModule -Destination $OutputDirectory\ -Force -Recurse -ErrorAction Stop
        Copy-Item $PSScriptRoot\Deploy.ps1 -Destination $OutputDirectory\Deploy.ps1 -Force -ErrorAction Stop
        Copy-Item $PSScriptRoot\Dsc.Configuration.nuspec -Destination $OutputDirectory\Dsc.Configuration.nuspec -Force -ErrorAction Stop
    }
    catch
    {
        Write-Error -ErrorRecord $_
        exit 1
    }
}

function RunUnitTests
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    Import-Module Pester -ErrorAction Stop

    $testResults = Invoke-Pester -Path $Path -PassThru
    if ($testResults.FailedCount -gt 0)
    {
        throw 'One or more unit tests failed to pass.  Build aborting.'
    }
}

function TestDscResources
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    $allResources = Get-DscResource | Where-Object { $_.ImplementedAs -eq 'PowerShell' }
    $moduleDirectories = Get-ChildItem -Path $Path -Directory

    $failedResources = @(
        foreach ($moduleDirectory in $moduleDirectories)
        {
            $moduleResources = $allResources | Where-Object {
                $null -ne $_.Module -and $_.Module.Name -eq $moduleDirectory.Name
            }

            foreach ($resource in $moduleResources)
            {
                if ($resource.Path)
                {
                    $resourceNameOrPath = Split-Path $resource.Path -Parent
                }
                else
                {
                    $resourceNameOrPath = $resource.Name
                }

                Write-Verbose "Running Test-cDscResource -Name '$resourceNameOrPath'"

                if (-not (Test-cDscResource -Name $resourceNameOrPath))
                {
                    $resource
                }
            }
        }
    )

    if ($failedResources.Count -gt 0)
    {
        $failedNames = $failedResources.Name -join ', '
        throw "The following resources did not pass the Test-cDscResource command: $failedNames"
    }
}

function CompileTestMOFs
{
    $roles = @(
        'Web'
        'Database'
    )

    Import-Module DemoConfiguration -ErrorAction Stop

    foreach ($role in $roles)
    {
        # We'll need to add mock values for any Octopus variables that the configuration script treats as
        # mandatory here, in addition to Octopus.Machine.Roles

        $parameters = @{
            'Octopus.Machine.Roles' = $role
        }

        try
        {
            DemoConfiguration -OctopusParameters $parameters -ErrorAction Stop -OutputPath $env:temp\MOF
        }
        catch
        {
            throw "Error compiling SampleConfiguration with the following role: $role.  Error message:  $($_.Exception.Message)"
        }
    }
}

function DeployResourceModules
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    $moduleDirectories = Get-ChildItem -LiteralPath $Source -Directory -ErrorAction Stop

    foreach ($moduleDirectory in $moduleDirectories)
    {
        $target = Join-Path $Destination $moduleDirectory.Name
        $deployPs1 = Join-Path $moduleDirectory.FullName Deploy.ps1

        if (Test-Path -LiteralPath $deployPs1 -PathType Leaf)
        {
            $null = & $deployPs1 $target
        }
        else
        {
            if (Test-Path -LiteralPath $target)
            {
                Remove-Item -LiteralPath $target -Force -Recurse -ErrorAction Stop
            }

            $null = New-Item -Path $target -ItemType Directory -ErrorAction Stop

            Copy-Item "$($moduleDirectory.FullName)\*" "$target\" -Recurse -Force -ErrorAction Stop
        }
    }
}

Main -OutputDirectory $OutputDirectory

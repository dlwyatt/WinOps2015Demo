Add-Type -Path $PSScriptRoot\..\..\PolFileEditor.dll -ErrorAction Stop
. "$PSScriptRoot\..\..\Commands.ps1"

function Get-TargetResource
{
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string] $Account,

        [Parameter(Mandatory)]
        [string] $KeyValueName
    )

    try
    {
        $path = GetPolFilePath -Account $Account -ErrorAction Stop
        return GetTargetResourceCommon -Path $path -KeyValueName $KeyValueName
    }
    catch
    {
        Write-Error -ErrorRecord $_
        return
    }
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [string] $Account,

        [Parameter(Mandatory)]
        [string] $KeyValueName,

        [ValidateSet('Present', 'Absent')]
        [string] $Ensure = 'Present',

        [string[]] $Data,

        [Microsoft.Win32.RegistryValueKind] $Type = [Microsoft.Win32.RegistryValueKind]::String
    )

    try
    {
        $path = GetPolFilePath -Account $Account -ErrorAction Stop
        SetTargetResourceCommon -Path $path -KeyValueName $KeyValueName -Ensure $Ensure -Data $Data -Type $Type
    }
    catch
    {
        Write-Error -ErrorRecord $_
        return
    }
}

function Test-TargetResource
{
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string] $Account,

        [Parameter(Mandatory)]
        [string] $KeyValueName,

        [ValidateSet('Present', 'Absent')]
        [string] $Ensure = 'Present',

        [string[]] $Data,

        [Microsoft.Win32.RegistryValueKind] $Type = [Microsoft.Win32.RegistryValueKind]::String
    )

    try
    {
        $path = GetPolFilePath -Account $Account -ErrorAction Stop
        return TestTargetResourceCommon -Path $path -KeyValueName $KeyValueName -Ensure $Ensure -Data $Data -Type $Type
    }
    catch
    {
        Write-Error -ErrorRecord $_
        return
    }
}

Export-ModuleMember Get-TargetResource, Test-TargetResource, Set-TargetResource

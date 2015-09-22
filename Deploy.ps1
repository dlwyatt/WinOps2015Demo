#requires -Version 4.0
#requires -RunAsAdministrator

end
{
    try
    {
        $oldModuleTarget = "$env:ProgramFiles\WindowsPowerShell\Modules"
        $moduleTarget = "$pshome\Modules"

        foreach ($moduleFolder in Get-ChildItem -LiteralPath $PSScriptRoot\Modules -Directory)
        {
            $name = $moduleFolder.Name
            Copy-Folder -Source $moduleFolder.FullName -Destination $moduleTarget\$name -ErrorAction Stop

            if (Test-Path -Path $oldModuleTarget\$name -PathType Container)
            {
                Remove-Item -Path $oldModuleTarget\$name -Recurse -Force -ErrorAction Ignore
            }
        }

        $certFilePath = GetDscCertFilePath
        ConfigureLCM -CertPath $certFilePath

        $configData = @{
            AllNodes = @(
                @{ NodeName = 'localhost'; CertificateFile = $certFilePath }
            )
        }

        Import-Module $PSScriptRoot\DemoConfiguration -ErrorAction Stop

        $null = DemoConfiguration -OctopusParameters $OctopusParameters -OutputPath $env:temp\MOF -ConfigurationData $configData -ErrorAction Stop
        Start-DscConfiguration -Path $env:temp\MOF -Force -Wait -Verbose -ErrorAction Stop
    }
    catch
    {
        Write-Error -ErrorRecord $_
        exit 1
    }

    exit 0
}

begin
{
    function GetDscCertFilePath
    {
        $lcmSettings = Get-DscLocalConfigurationManager
        $certToExport = $null

        $thumbprint = $lcmSettings.CertificateID

        if ($thumbprint)
        {
            $path = Join-Path Cert:\LocalMachine\My $thumbprint
            if (Test-Path -LiteralPath $path)
            {
                $cert = Get-Item -LiteralPath $path
                if ($cert.HasPrivateKey)
                {
                    $certToExport = $cert
                }
            }
        }

        if ($null -eq $certToExport)
        {
            $certToExport = Get-ChildItem -LiteralPath Cert:\LocalMachine\My |
                            Where-Object { $_.HasPrivateKey -and $_.Subject -eq 'CN=DscEncryption' } |
                            Select-Object -First 1

            if ($null -eq $certToExport)
            {
                $certToExport = NewDscCertificate
            }
        }

        if ($null -eq $certToExport)
        {
            throw 'Error:  $certToExport was still null when the code reached the point of calling Export-Certificate.'
        }

        $filePath = Join-Path $env:temp DscEncryption.cer
        $null = $certToExport | Export-Certificate -FilePath $filePath -Force -Type CERT -ErrorAction Stop

        return $filePath
    }

    function NewDscCertificate
    {
        $requestfile = [System.IO.Path]::GetTempFileName()
        $certFile = [System.IO.Path]::GetTempFileName()

        Set-Content -Path $requestfile -Encoding Ascii -Value @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=DscEncryption"
KeyLength = 2048
Exportable = TRUE
FriendlyName = "ProtectedData"
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
RequestType = Cert
Silent = True
SuppressDefaults = True
KeySpec = AT_KEYEXCHANGE
KeyUsage = CERT_KEY_ENCIPHERMENT_KEY_USAGE
NotAfter = "$((Get-Date).AddYears(20).ToString('G'))"
"@

        try
        {
            $oldCerts = @(
                Get-ChildItem Cert:\LocalMachine\My |
                Where-Object { $_.Subject -eq 'CN=DscEncryption' } |
                Select-Object -ExpandProperty Thumbprint
            )

            $result = certreq.exe -new -f -machine -q $requestfile $certFile

            if ($LASTEXITCODE -ne 0)
            {
                throw $result
            }

            $newCert = Get-ChildItem Cert:\LocalMachine\My -Exclude $oldCerts |
                       Where-Object { $_.Subject -eq 'CN=DscEncryption' }

            return $newCert
        }
        finally
        {
            Remove-Item -Path $requestfile -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $certFile -Force -ErrorAction SilentlyContinue
        }
    }

    function ConfigureLCM
    {
        param (
            [string] $CertPath
        )

        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]$CertPath

        configuration LCM
        {
            node localhost
            {
                LocalConfigurationManager
                {
                    CertificateID        = $cert.Thumbprint
                    ActionAfterReboot    = 'ContinueConfiguration'
                    RebootNodeIfNeeded   = $true
                    ConfigurationMode    = 'ApplyAndAutoCorrect'
                    AllowModuleOverwrite = $true
                    DebugMode            = 'ForceModuleImport'
                }
            }
        }

        $null = LCM -OutputPath $env:temp\LCM
        $null = Set-DscLocalConfigurationManager -Path $env:temp\LCM -ErrorAction Stop

    }

    # Quick and dirty implementation of what is basically Robocopy.exe /MIR, except instead of relying on file sizes and modified dates, it
    # calculates file hashes instead.  Not intended for use over the network; this is for local installation scripts in nuget packages.

    # This will help us to avoid "file in use" errors for dlls that haven't changed, and that sort of thing.

    function Copy-Folder
    {
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Parameter(Mandatory)]
            [ValidateScript({
                if (-not (Test-Path -LiteralPath $_) -or
                    (Get-Item -LiteralPath $_) -isnot [System.IO.DirectoryInfo])
                {
                    throw "Path '$_' does not refer to a Directory on the FileSystem provider."
                }

                return $true
            })]
            [string] $Source,

            [Parameter(Mandatory)]
            [ValidateScript({
                if (Test-Path -LiteralPath $_)
                {
                    $destFolder = Get-Item -LiteralPath $_ -ErrorAction Stop -Force

                    if ($destFolder -isnot [System.IO.DirectoryInfo])
                    {
                        throw "Destination '$_' exists, and is not a directory on the file system."
                    }
                }

                return $true
            })]
            [string] $Destination
        )

        # Everything here that's destructive is done via cmdlets that already support ShouldProcess, so we don't need to make our own calls
        # to it here.  Those cmdlets will inherit our local $WhatIfPreference / $ConfirmPreference anyway.

        $sourceFolder = Get-Item -LiteralPath $Source
        $sourceRootPath = $sourceFolder.FullName

        if (Test-Path -LiteralPath $Destination)
        {
            $destFolder = Get-Item -LiteralPath $Destination -ErrorAction Stop -Force

            # ValidateScript already made sure that we're looking at a [DirectoryInfo], but just in case there's a weird race condition
            # with some other process, we'll check again here to be sure.

            if ($destFolder -isnot [System.IO.DirectoryInfo])
            {
                throw "Destination '$Destination' exists, and is not a directory on the file system."
            }

            # First, clear out anything in the destination that doesn't exist in the source.  By doing this first, we can ensure that
            # there aren't existing directories with the name of a file we need to copy later, or vice versa.

            foreach ($fsInfo in Get-ChildItem -LiteralPath $destFolder.FullName -Recurse -Force)
            {
                # just in case we've already nuked the parent folder of something earlier in the loop.
                if (-not $fsInfo.Exists) { continue }

                $fsInfoRelativePath = Get-RelativePath -Path $fsInfo.FullName -RelativeTo $destFolder.FullName
                $sourcePath = Join-Path $sourceRootPath $fsInfoRelativePath

                if ($fsInfo -is [System.IO.DirectoryInfo])
                {
                    $pathType = 'Container'
                }
                else
                {
                    $pathType = 'Leaf'
                }

                if (-not (Test-Path -LiteralPath $sourcePath -PathType $pathType))
                {
                    Remove-Item $fsInfo.FullName -Force -Recurse -ErrorAction Stop
                }
            }
        }

        # Now copy over anything from source that's either missing or different.
        foreach ($fsInfo in Get-ChildItem -LiteralPath $sourceRootPath -Recurse -Force)
        {
            $fsInfoRelativePath = Get-RelativePath -Path $fsInfo.FullName -RelativeTo $sourceRootPath
            $targetPath = Join-Path $Destination $fsInfoRelativePath
            $parentPath = Split-Path $targetPath -Parent

            if ($fsInfo -is [System.IO.FileInfo])
            {
                EnsureFolderExists -Path $parentPath

                if (-not (Test-Path -LiteralPath $targetPath) -or
                    -not (FilesAreIdentical $fsInfo.FullName $targetPath))
                {
                    Copy-Item -LiteralPath $fsInfo.FullName -Destination $targetPath -Force -ErrorAction Stop
                }
            }
            else
            {
                EnsureFolderExists -Path $targetPath
            }
        }
    }

    function EnsureFolderExists([string] $Path)
    {
        if (-not (Test-Path -LiteralPath $Path -PathType Container))
        {
            $null = New-Item -Path $Path -ItemType Directory -ErrorAction Stop
        }
    }

    function FilesAreIdentical([string] $FirstPath, [string] $SecondPath)
    {
        $first = Get-Item -LiteralPath $FirstPath -Force -ErrorAction Stop
        $second = Get-Item -LiteralPath $SecondPath -Force -ErrorAction Stop

        if ($first.Length -ne $second.Length) { return $false }

        $firstHash = Get-FileHash -LiteralPath $FirstPath -Algorithm SHA512 -ErrorAction Stop
        $secondHash = Get-FileHash -LiteralPath $SecondPath -Algorithm SHA512 -ErrorAction Stop

        return $firstHash.Hash -eq $secondHash.Hash
    }

    function Get-RelativePath([string] $Path, [string]$RelativeTo )
    {
        $RelativeTo = $RelativeTo -replace '\\+$'
        return $Path -replace "^$([regex]::Escape($RelativeTo))\\?"
    }
}


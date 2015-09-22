$modulePath = Join-Path $PSScriptRoot ..\PSHOrg_cPackageResource.psm1

$module = $null
$prefix = [guid]::NewGuid().Guid -replace '[^a-f\d]'

try
{
    $module = Import-Module -Name $modulePath -ErrorAction Stop -Force -Prefix $prefix -PassThru

    InModuleScope $module.Name {
        Describe 'Verifying downloaded files' {
            # These tests use Microsoft's installer for fciv.exe, which is an extract-only exe file (does not add anything to Add/Remove Programs.)

            Mock Test-TargetResource { return $false }

            # The resource performs a post-validation check when installing executables; if the result of Get-ProductEntry
            # is $null, it throws an error.  We're not testing for that, so mocking Get-ProductEntry to return any non-null
            # value suppresses the error.
            Mock Get-ProductEntry { return [pscustomobject]@{} }

            Setup -Dir Extract
            $extractPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('TestDrive:\Extract')
            $fcivPath = Join-Path $extractPath fciv.exe
            $installerPath = Join-Path $PSScriptRoot Windows-KB841290-x86-ENU.exe

            BeforeEach {
                Get-ChildItem -LiteralPath $extractPath -Force -ErrorAction Stop |
                Remove-Item -Force -ErrorAction Stop
            }

            Context 'Verification by file hash' {
                $testCases = @(
                    @{ Algorithm = 'SHA1';         Hash = '99FB35D97A5EE0DF703F0CDD02F2D787D6741F65' }
                    @{ Algorithm = 'SHA256';       Hash = '4B1FEEA09F35F30943220E8C493A7E590739607A2315559F26B84B3586A5DD54' }
                    @{ Algorithm = 'SHA384';       Hash = '5D671E27B069AB605EC9962D3D26D80D69AECC568266D50296A72E56AF4D822198156C6431C72C83D82FC704610C6E59' }
                    @{ Algorithm = 'SHA512';       Hash = 'E7C919B7D8DB1E9C915E2D1CB4E0330E15124C031154D5E5C9309A88FC4D2AD3E91035176BC58A2A0B8D88BA29A53E834AFA38FF6DB886CD1C345B8B11199799' }
                    @{ Algorithm = 'MD5';          Hash = '58DC4DF814685A165F58037499C89E76' }
                    @{ Algorithm = 'RIPEMD160';    Hash = '5D4EE2F27437119F7B8BDAE7C65B2575EE3940AD' }
                )

                It 'Verifies a file by hash using algorithm <Algorithm>' -TestCases $testCases {
                    param ([string] $Algorithm, [string] $Hash)

                    $scriptBlock = {
                        Set-TargetResource -Name          __DoesNotMatter__ `
                                           -Path          $installerPath `
                                           -ProductId     ([string]::Empty) `
                                           -Arguments     "/Q /T:`"$extractPath`"" `
                                           -HashAlgorithm $Algorithm `
                                           -FileHash      $Hash `
                                           -Ensure        Present

                    }

                    $scriptBlock | Should Not Throw
                    $fcivPath | Should Exist
                }

                It 'Correctly throws an error when an incorrect <Algorithm> hash is detected.' -TestCases $testCases {
                    param ([string] $Algorithm, [string] $Hash)

                    $scriptBlock = {
                        Set-TargetResource -Name          __DoesNotMatter__ `
                                           -Path          $installerPath `
                                           -ProductId     ([string]::Empty) `
                                           -Arguments     "/Q /T:`"$extractPath`"" `
                                           -HashAlgorithm $Algorithm `
                                           -FileHash      "$Hash-DeliberatelyWrong" `
                                           -Ensure        Present

                    }

                    $scriptBlock | Should Throw
                    $fcivPath | Should Not Exist
                }
            }

            Context 'Verification by digital signature' {
                $actualSignerThumbprint = '2A1049B2557DE78CF6592BF68504E23C91ADBF8C'
                $actualSignerSubject    = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'

                It 'Verifies the file by signer thumbprint' {
                    $scriptBlock = {
                        Set-TargetResource -Name             __DoesNotMatter__ `
                                           -Path             $installerPath `
                                           -ProductId        ([string]::Empty) `
                                           -Arguments        "/Q /T:`"$extractPath`"" `
                                           -SignerThumbprint $actualSignerThumbprint `
                                           -Ensure           Present

                    }

                    $scriptBlock | Should Not Throw
                    $fcivPath | Should Exist
                }

                It 'Does not install a file with the wrong signer thumbprint' {
                    $scriptBlock = {
                        Set-TargetResource -Name             __DoesNotMatter__ `
                                           -Path             $installerPath `
                                           -ProductId        ([string]::Empty) `
                                           -Arguments        "/Q /T:`"$extractPath`"" `
                                           -SignerThumbprint "$actualSignerThumbprint-DeliberatelyWrong" `
                                           -Ensure           Present

                    }

                    $scriptBlock | Should Throw
                    $fcivPath | Should Not Exist
                }

                It 'Verifies the file by signer Subject' {
                    $scriptBlock = {
                        Set-TargetResource -Name          __DoesNotMatter__ `
                                           -Path          $installerPath `
                                           -ProductId     ([string]::Empty) `
                                           -Arguments     "/Q /T:`"$extractPath`"" `
                                           -SignerSubject $actualSignerSubject `
                                           -Ensure        Present

                    }

                    $scriptBlock | Should Not Throw
                    $fcivPath | Should Exist
                }

                It 'Allows wildcards to be used when verifying by subject.' {
                    $scriptBlock = {
                        Set-TargetResource -Name          __DoesNotMatter__ `
                                           -Path          $installerPath `
                                           -ProductId     ([string]::Empty) `
                                           -Arguments     "/Q /T:`"$extractPath`"" `
                                           -SignerSubject * `
                                           -Ensure        Present

                    }

                    $scriptBlock | Should Not Throw
                    $fcivPath | Should Exist
                }

                It 'Does not install a file with the wrong signer subject' {
                    $scriptBlock = {
                        Set-TargetResource -Name          __DoesNotMatter__ `
                                           -Path          $installerPath `
                                           -ProductId     ([string]::Empty) `
                                           -Arguments     "/Q /T:`"$extractPath`"" `
                                           -SignerSubject "$actualSignerSubject-DeliberatelyWrong" `
                                           -Ensure        Present

                    }

                    $scriptBlock | Should  Throw
                    $fcivPath | Should Not Exist
                }
            }
        }
    }
}
finally
{
    if ($module) { Remove-Module -ModuleInfo $module }
}

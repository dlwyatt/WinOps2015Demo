configuration DemoConfiguration
{
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $OctopusParameters
    )

    Import-DscResource -ModuleName DOG_OctopusDeployResources
    Import-DscResource -ModuleName cWebAdministration
    Import-DscResource -ModuleName cNetworking
    Import-DscResource -ModuleName PolicyFileEditor
    Import-DscResource -ModuleName cPSDesiredStateConfiguration

    node localhost
    {
        $roles = $OctopusParameters['Octopus.Machine.Roles'] -split ','

        cOctopusDeployTentacle Tentacle
        {
            TentacleName         = 'Tentacle'
            ServerName           = '192.168.50.1'
            ServerThumbprint     = '324F816071ED1E599C384839860F1B89C18F1581'
            CommunicationMode    = 'Listen'
            TentacleInstallerUrl = 'c:\vagrant\temp\Octopus.Tentacle.3.0.4.2105-x64.msi'
        }

        cAdministrativeTemplateSetting AllowMultipleRdpSessions
        {
            Ensure       = 'Present'
            PolicyType   = 'Machine'
            KeyValueName = 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\fSingleSessionPerUser'
            Type         = 'DWord'
            Data         = '0'
        }

        if ($roles -contains 'Web')
        {
            WindowsFeature AspDotNet45Core
            {
                Name   = 'Net-Framework-45-ASPNET'
                Ensure = 'Present'
            }

            WindowsFeature IIS
            {
                Name      = 'Web-Server'
                Ensure    = 'Present'
                DependsOn = '[WindowsFeature]AspDotNet45Core'
            }

            WindowsFeature IISAdmin
            {
                Name      = 'Web-Mgmt-Console'
                Ensure    = 'Present'
                DependsOn = '[WindowsFeature]IIS'
            }

            WindowsFeature AspDotNet45
            {
                Name      = 'Web-Asp-Net45'
                Ensure    = 'Present'
                DependsOn = '[WindowsFeature]IIS'
            }

            WindowsFeature IsapiExtensions
            {
                Name      = 'Web-ISAPI-Ext'
                Ensure    = 'Present'
                DependsOn = '[WindowsFeature]IIS'
            }

            WindowsFeature IsapiFilters
            {
                Name      = 'Web-ISAPI-Filter'
                Ensure    = 'Present'
                DependsOn = '[WindowsFeature]IIS'
            }

            WindowsFeature DotNetExtensibility45
            {
                Name      = 'Web-Net-Ext45'
                Ensure    = 'Present'
                DependsOn = '[WindowsFeature]IIS'
            }

            cWebsite RemoveDefaultSite
            {
                Ensure       = 'Absent'
                Name         = 'Default Web Site'
                PhysicalPath = 'Mandatory Property - Ignored on Ensure = Absent'
                DependsOn    = '[WindowsFeature]IIS'
            }

            cAppPool RemoveDefaultAppPool
            {
                Ensure    = 'Absent'
                Name      = 'DefaultAppPool'
                DependsOn = '[WindowsFeature]IIS'
            }
        }

        if ($roles -contains 'Database')
        {
            File dbFlag
            {
                DestinationPath = 'C:\DscFile.txt'
                Contents        = 'I am a database server.  Honest! - v3'
            }
        }
    }
}

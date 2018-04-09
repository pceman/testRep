#
# xSqlAvailabilityGroupListener: DSC resource that configures a SQL AlwaysOn Availability Group Listener.
#

function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $AvailabilityGroupName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $DomainNameFqdn,

        [String[]] $ListenerIPAddresses,

        [UInt32] $ListenerPortNumber = 1433,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    $bConfigured = Test-TargetResource -Name $Name -AvailabilityGroupName $AvailabilityGroupName -DomainNameFqdn $DomainNameFqdn -ListenerPortNumber $ListenerPortNumber -InstanceName  $InstanceName -DomainCredential $DomainCredential -SqlAdministratorCredential $SqlAdministratorCredential

    $returnValue = @{
        Name = $Name
        AvailabilityGroupName = $AvailabilityGroupName
        DomainNameFqdn = $DomainNameFqdn
        ListenerPortNumber = $ListenerPortNumber
        InstanceName = $InstanceName
        DomainCredential = $DomainCredential.UserName
        SqlAdministratorCredential = $SqlAdministratorCredential.UserName
        Configured = $bConfigured
    }

    $returnValue
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $AvailabilityGroupName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $DomainNameFqdn,

        [String[]] $ListenerIPAddresses,

        [UInt32] $ListenerPortNumber = 1433,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    Write-Verbose -Message "Configuring the Availability Group Listener port to '$($ListenerPortNumber)' ..."
    
    Remove-Module SQLPS -ErrorAction SilentlyContinue
    Import-Module SQLPS

    $s = New-Object Microsoft.SqlServer.Management.Smo.Server($env:COMPUTERNAME)
    $ag = $s.AvailabilityGroups[$AvailabilityGroupName]
    $sPrimary = New-Object Microsoft.SqlServer.Management.Smo.Server($ag.PrimaryReplicaServerName)
    $agPrimary = $sPrimary.AvailabilityGroups[$AvailabilityGroupName]

    $subnetMask=(Get-ClusterNetwork)[0].AddressMask
    $aglIpAddresses = @()
    $aglIpAddresses += "$($ListenerIPAddresses[0])/$subnetMask"
    
    for ($count=1; $count -le $ListenerIPAddresses.Length - 1; $count++) {
        $subnetMask=(Get-ClusterNetwork)[$($count % 3)].AddressMask
        $aglIpAddresses += "$($ListenerIPAddresses[$count])/$subnetMask"
    }
    
    New-SqlAvailabilityGroupListener -Name $Name -StaticIp $aglIpAddresses -Port $ListenerPortNumber -InputObject $agPrimary
    
}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $AvailabilityGroupName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $DomainNameFqdn,

        [String[]] $ListenerIPAddresses,

        [UInt32] $ListenerPortNumber = 1433,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    Remove-Module SQLPS -ErrorAction SilentlyContinue
    Import-Module SQLPS

    Write-Verbose -Message "Checking if SQL AG Listener '$($Name)' exists on instance '$($InstanceName)' ..."

    $instance = Get-SqlInstanceName -Node  $env:COMPUTERNAME -InstanceName $InstanceName
    $s = Get-SqlServer -InstanceName $instance -Credential $SqlAdministratorCredential

    $ag = $s.AvailabilityGroups
    $agl = $ag.AvailabilityGroupListeners
    $bRet = $true

    if ($agl)
    {
        Write-Verbose -Message "SQL AG Listener '$($Name)' found."
    }
    else
    {
        Write-Verbose "SQL AG Listener '$($Name)' NOT found."
        $bRet = $false
    }

    return $bRet
}


function Get-SqlServer([string]$InstanceName, [PSCredential]$Credential)
{
    $sc = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
    $sc.ServerInstance = $InstanceName
    $sc.ConnectAsUser = $true
    if ($Credential.GetNetworkCredential().Domain -and $Credential.GetNetworkCredential().Domain -ne $env:COMPUTERNAME)
    {
        $sc.ConnectAsUserName = "$($Credential.GetNetworkCredential().UserName)@$($Credential.GetNetworkCredential().Domain)"
    }
    else
    {
        $sc.ConnectAsUserName = $Credential.GetNetworkCredential().UserName
    }
    $sc.ConnectAsUserPassword = $Credential.GetNetworkCredential().Password
    
    $s = New-Object Microsoft.SqlServer.Management.Smo.Server $sc

    $s
}

function Get-SqlInstanceName([string]$Node, [string]$InstanceName)
{
    $pureInstanceName = Get-PureSqlInstanceName -InstanceName $InstanceName
    if ("MSSQLSERVER" -eq $pureInstanceName)
    {
        $Node
    }
    else
    {
        $Node + "\" + $pureInstanceName
    }
}

function Get-PureSqlInstanceName([string]$InstanceName)
{
    $list = $InstanceName.Split("\")
    if ($list.Count -gt 1)
    {
        $list[1]
    }
    else
    {
        "MSSQLSERVER"
    }
}

function Get-SqlAvailabilityGroup([string]$Name, [Microsoft.SqlServer.Management.Smo.Server]$Server)
{
    $s.AvailabilityGroups | where { $_.Name -eq $Name }
}

Export-ModuleMember -Function *-TargetResource

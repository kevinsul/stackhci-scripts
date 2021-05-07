#########################SET ALL VARIABLES###########################
#Set Name of Node01
$Node01 = "XXXXX"

#Set Name of Node02
$Node02 = "XXXXX"

#Set IP Address for Node01
$Node01IP = "XXX.XXX.XXX.XXX"

#Set IP Address for Node02
$Node02IP = "XXX.XXX.XXX.XXX"

#Set Default GW IP
$GWIP = "XXX.XXX.XXX.XXX"

#Set Compute vSwitch Names
$vSwitch1 = "XXXXX"
$vSwitch2 = "XXXXX"

#Set Host vNIC Name and Alias
$HostvNIC = "XXXXX"
$HostvNICAlias = "vEthernet (" + $HostvNIC + ")"

#Set IP of AD DNS Server
$DNSIP = "XXX.XXX.XXX.XXX"

#Set Server List 
$ServerList = $Node01, $Node02

#Set Cluster Name and Cluster IP
$ClusterName = "XXXXX"
$ClusterIP = "XXX.XXX.XXX.XXX"

#Set Cred for Local HCI Node
$Localpassword = ConvertTo-SecureString "XXXXX" -AsPlainText -Force
$LocalCred = New-Object System.Management.Automation.PSCredential ("XXXXX", $Localpassword)

#Set name of AD Domain
$ADDomain = "azure.local"

#Set AD Domain Cred
$ADpassword = ConvertTo-SecureString "XXXXX" -AsPlainText -Force
$ADCred = New-Object System.Management.Automation.PSCredential ("XXXXX\XXXXX", $ADpassword)

#Set Cred for AAD tenant and subscription
$AADpassword = ConvertTo-SecureString "AzureHybridRocks1!" -AsPlainText -Force
$AADCred = New-Object System.Management.Automation.PSCredential ("XXXXX@XXXXX.XXX", $AADpassword)
$AzureSubID = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
###############################################################################################################################

#Set WinRM for remote management of nodes
winrm quickconfig
Set-Item WSMan:\localhost\Client\TrustedHosts $Node01IP -Concatenate -Force
Set-Item WSMan:\localhost\Client\TrustedHosts $Node02IP -Concatenate -Force

#Install some PS modules if not already installed
Install-WindowsFeature -Name RSAT-Clustering,RSAT-Clustering-Mgmt,RSAT-Clustering-PowerShell,RSAT-Hyper-V-Tools

##########################################Configure Node01####################################################################
#Add features, add PS modules, rename, join domain, reboot
Invoke-Command -ComputerName $Node01 -ScriptBlock {
    Install-WindowsFeature -Name "BitLocker", "Data-Center-Bridging", "Failover-Clustering", "FS-FileServer", "FS-Data-Deduplication", "Hyper-V", "Hyper-V-PowerShell", "RSAT-AD-Powershell", "RSAT-Clustering-PowerShell", "Storage-Replica" -IncludeAllSubFeature -IncludeManagementTools
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name Az -Force -All
    Install-Module -Name Az.StackHCI -Force -All
	}

Restart-Computer -ComputerName $Node01 -Protocol WSMan -Wait -For PowerShell -Force

#Pause for a bit - let changes apply before moving on...
sleep 120

#Create SET vSwitches, enable RDMA, set MGMT vNIC, Configure Storage NICs
Invoke-Command -ComputerName $Node01 -ScriptBlock {
    # Create SET-enabled vSwitch for Hyper-V using 1GbE ports
    New-VMSwitch -Name $using:vSwitch1 -NetAdapterName "LOM2 Port3" -EnableEmbeddedTeaming $true -AllowManagementOS $false
    New-VMSwitch -Name $using:vSwitch2 -NetAdapterName "LOM2 Port4" -EnableEmbeddedTeaming $true -AllowManagementOS $false

    # Add host vNIC to the vSwitch just created
    Add-VMNetworkAdapter -SwitchName $using:vSwitch1 -Name $using:HostvNIC -ManagementOS

    # Enable RDMA on 10GbE ports
    Enable-NetAdapterRDMA -Name "LOM1 Port1"
    Enable-NetAdapterRDMA -Name "LOM1 Port2"

    # Configure IP and subnet mask, no default gateway for Storage interfaces
    New-NetIPAddress -InterfaceAlias "LOM1 Port1" -IPAddress 172.16.0.1 -PrefixLength 24
    New-NetIPAddress -InterfaceAlias "LOM1 Port2" -IPAddress 172.16.1.1 -PrefixLength 24
    New-NetIPAddress -InterfaceAlias $using:HostvNICAlias -IPAddress $using:Node01IP -PrefixLength 24 -DefaultGateway $using:GWIP

    # Configure DNS on each interface, but do not register Storage interfaces
    Set-DnsClient -InterfaceAlias "LOM1 Port1" -RegisterThisConnectionsAddress $false
    Set-DnsClientServerAddress -InterfaceAlias "LOM1 Port1" -ServerAddresses $using:DNSIP
    Set-DnsClient -InterfaceAlias "LOM1 Port2" -RegisterThisConnectionsAddress $false
    Set-DnsClientServerAddress -InterfaceAlias "LOM1 Port2" -ServerAddresses $using:DNSIP
    Set-DnsClientServerAddress -InterfaceAlias $using:HostvNICAlias -ServerAddresses $using:DNSIP
	}
#########################################################################################################################################

############################################################Configure Node02#############################################################
#Add features, add PS modules, rename, join domain, reboot
Invoke-Command -ComputerName $Node02 -Credential $ADCred -ScriptBlock {
    Install-WindowsFeature -Name "BitLocker", "Data-Center-Bridging", "Failover-Clustering", "FS-FileServer", "FS-Data-Deduplication", "Hyper-V", "Hyper-V-PowerShell", "RSAT-AD-Powershell", "RSAT-Clustering-PowerShell", "Storage-Replica" -IncludeAllSubFeature -IncludeManagementTools 
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name Az -Force -ALL
    Install-Module -Name Az.StackHCI -Force -All
	}

Restart-Computer -ComputerName $Node02 -Protocol WSMan -Wait -For PowerShell -Force

#Pause for a bit - let changes apply before moving on...
sleep 120

#Create SET vSwitches, enable RDMA, set MGMT vNIC, Configure Storage NICs
Invoke-Command -ComputerName $Node02 -ScriptBlock {
    # Create SET-enabled vSwitch for Hyper-V using 1GbE ports
    New-VMSwitch -Name $using:vSwitch1 -NetAdapterName "LOM2 Port3" -EnableEmbeddedTeaming $true -AllowManagementOS $false
    New-VMSwitch -Name $using:vSwitch2 -NetAdapterName "LOM2 Port4" -EnableEmbeddedTeaming $true -AllowManagementOS $false

    # Add host vNIC to the vSwitch just created
    Add-VMNetworkAdapter -SwitchName $using:vSwitch1 -Name $using:HostvNIC -ManagementOS

    # Enable RDMA on 10GbE ports
    Enable-NetAdapterRDMA -Name "LOM1 Port1"
    Enable-NetAdapterRDMA -Name "LOM1 Port2"

    # Configure IP and subnet mask, no default gateway for Storage interfaces
    New-NetIPAddress -InterfaceAlias "LOM1 Port1" -IPAddress 172.16.0.2 -PrefixLength 24
    New-NetIPAddress -InterfaceAlias "LOM1 Port2" -IPAddress 172.16.1.2 -PrefixLength 24
    New-NetIPAddress -InterfaceAlias $using:HostvNICAlias -IPAddress $using:Node02IP -PrefixLength 24 -DefaultGateway $using:GWIP

    # Configure DNS on each interface, but do not register Storage interfaces
    Set-DnsClient -InterfaceAlias "LOM1 Port1" -RegisterThisConnectionsAddress $false
    Set-DnsClientServerAddress -InterfaceAlias "LOM1 Port1" -ServerAddresses $using:DNSIP
    Set-DnsClient -InterfaceAlias "LOM1 Port2" -RegisterThisConnectionsAddress $false
    Set-DnsClientServerAddress -InterfaceAlias "LOM1 Port2" -ServerAddresses $using:DNSIP
    Set-DnsClientServerAddress -InterfaceAlias $using:HostvNICAlias -ServerAddresses $using:DNSIP
	}
#########################################################################################################################################

#########################################################Configure HCI Cluster##########################################################
#Clear Storage
Invoke-Command ($ServerList) {
    Update-StorageProviderCache
    Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -IsReadOnly:$false -ErrorAction SilentlyContinue
    Get-StoragePool | ? IsPrimordial -eq $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
    Get-StoragePool | ? IsPrimordial -eq $false | Remove-StoragePool -Confirm:$false -ErrorAction SilentlyContinue
    Get-PhysicalDisk | Reset-PhysicalDisk -ErrorAction SilentlyContinue
    Get-Disk | ? Number -ne $null | ? IsBoot -ne $true | ? IsSystem -ne $true | ? PartitionStyle -ne RAW | % {
        $_ | Set-Disk -isoffline:$false
        $_ | Set-Disk -isreadonly:$false
        $_ | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
        $_ | Set-Disk -isreadonly:$true
        $_ | Set-Disk -isoffline:$true
    }
    Get-Disk | Where Number -Ne $Null | Where IsBoot -Ne $True | Where IsSystem -Ne $True | Where PartitionStyle -Eq RAW | Group -NoElement -Property FriendlyName
} | Sort -Property PsComputerName, Count

#Create the Cluster
Test-Cluster –Node $Node01, $Node02 –Include "Storage Spaces Direct", "Inventory", "Network", "System Configuration"
New-Cluster -Name $ClusterName -Node $Node01, $Node02 -StaticAddress $ClusterIP -NoStorage

#Pause for a bit then clear DNS cache.
sleep 30
Clear-DnsClientCache

# Update the cluster network names that were created by default.  First, look at what's there
Get-ClusterNetwork -Cluster $ClusterName  | ft Name, Role, Address

# Change the cluster network names so they are consistent with the individual nodes
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 1").Name = "Storage1"
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 2").Name = "Storage2"
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 3").Name = "OOB"
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 4").Name = "v410"

# Check to make sure the cluster network names were changed correctly
Get-ClusterNetwork -Cluster $ClusterName | ft Name, Role, Address

#Enable S2D
Enable-ClusterStorageSpacesDirect  -CimSession $ClusterName -PoolFriendlyName "Storage Pool 1" -Confirm:0

#CAN'T SET THIN!!! 
Set-StoragePool -CimSession $ClusterName -FriendlyName "Storage Pool 1" -ResiliencySettingNameDefault Mirror 

New-Volume -CimSession $ClusterName -StoragePoolFriendlyName "Storage Pool 1" -FriendlyName "Cluster Volume 1" -ResiliencySettingName Mirror -Size 2.5TB

#Set Cloud Witness
Set-ClusterQuorum -Cluster $ClusterName -Credential $AADCred -CloudWitness -AccountName XXXXX -AccessKey XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

#Register Cluster with Azure
Register-AzStackHCI -SubscriptionId $AzureSubID -ComputerName $Node01
############################################################################################################################################
#########################SET ALL VARIABLES########################### 
#Set Name of Node01
$Node01 = "MCDHCI1"

#Set Name of Node02
$Node02 = "MCDHCI2"

#Set Default GW IP
$GWIP = "10.50.10.1"

#Set Compute vSwitch Names
$vSwitch1 = "XXXXX"
$vSwitch2 = "XXXXX"

#Set Host vNIC Name and Alias
$HostvNIC = "vNIC-Host"
$HostvNICAlias = "vEthernet (" + $HostvNIC + ")"

#Set IP of AD DNS Server
$DNSIP = "10.20.200.40", "14.0.0.36"

#Set Server List 
$ServerList = $Node01, $Node02

#Set Cluster Name and Cluster IP
$ClusterName = "mcdhcicl"
$ClusterIP = "10.50.10.40"

#Set StoragePool Name
$global:StoragePoolName= "ASHCI Storage Pool 1"

#Set name of AD Domain
$ADDomain = "mycloudacademy.org"

#Set AD Domain Cred
$ADpassword = ConvertTo-SecureString "FlynnAndrea2018!!" -AsPlainText -Force
$ADCred = New-Object System.Management.Automation.PSCredential ("mca\mgodfre3", $ADpassword)

#Set Cred for AAD tenant and subscription
$AADAccount = "azstackadmin@azurestackdemo1.onmicrosoft.com"
$AADpassword = ConvertTo-SecureString "AzureHybridRocks1!
" -AsPlainText -Force
$AADCred = New-Object System.Management.Automation.PSCredential ("azstackadmin@azurestackdemo1.onmicrosoft.com", $AADpassword)
$AzureSubID = "0c6c3a0d-0866-4e68-939d-ef81ca6f802e"
###############################################################################################################################

#Set WinRM for remote management of nodes
winrm quickconfig

#Install some PS modules if not already installed
Install-WindowsFeature -Name RSAT-Clustering,RSAT-Clustering-Mgmt,RSAT-Clustering-PowerShell,RSAT-Hyper-V-Tools

##########################################Configure Nodes####################################################################
#Add features, add PS modules, rename, join domain, reboot
Invoke-Command -ComputerName $ServerList -Credential $ADCred -ScriptBlock {
    Install-WindowsFeature -Name "BitLocker", "Data-Center-Bridging", "Failover-Clustering", "FS-FileServer", "FS-Data-Deduplication", "Hyper-V", "Hyper-V-PowerShell", "RSAT-AD-Powershell", "RSAT-Clustering-PowerShell", "Storage-Replica", "NetworkATC" -IncludeAllSubFeature -IncludeManagementTools
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name Az.StackHCI -Force -All
}

Restart-Computer -ComputerName $ServerList -Protocol WSMan -Wait -For PowerShell -Force

#Pause for a bit - let changes apply before moving on...
sleep 180
###############################################################################################################################

##################################################Configure Node01#############################################################
Invoke-Command -ComputerName $Node01 -Credential $ADCred -ScriptBlock {

# Configure IP and subnet mask, no default gateway for Storage interfaces
    New-NetIPAddress -InterfaceAlias "LOM1 Port 1" -IPAddress 172.16.0.1 -PrefixLength 24
    New-NetIPAddress -InterfaceAlias "LOM1 Port 2" -IPAddress 172.16.1.1 -PrefixLength 24

#Add Temp NetIntent until Cluster is built
Add-NetIntent -ComputerName $Node01  -AdapterName "LOM Port 3", "LOM Port 4" -Name TempNSIntent -Compute -Management 

}


############################################################Configure Node02#############################################################
#Create SET vSwitches, enable RDMA, set MGMT vNIC, Configure Storage NICs
Invoke-Command -ComputerName $Node02 -Credential $ADCred -ScriptBlock {
    # Configure IP and subnet mask, no default gateway for Storage interfaces
    New-NetIPAddress -InterfaceAlias "LOM Port 1" -IPAddress 172.16.0.2 -PrefixLength 24
    New-NetIPAddress -InterfaceAlias "LOM Port 2" -IPAddress 172.16.1.2 -PrefixLength 24

    #Add Temp NetIntent until Cluster is built
    Add-NetIntent -ComputerName $Node02  -AdapterName "LOM Port 3", "LOM Port 4" -Name TempNSIntent -Compute -Management 
  

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
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 3").Name = "Storage1"
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 4").Name = "Storage2"
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 2").Name = "OOB"
(Get-ClusterNetwork -Cluster $ClusterName -Name "Cluster Network 1").Name = "MGMT"

# Check to make sure the cluster network names were changed correctly
Get-ClusterNetwork -Cluster $ClusterName | ft Name, Role, Address

#Set Cluster Live Migration Settings 
Enable-VMMigration -ComputerName $ServerList
Add-VMMigrationNetwork -computername $ServerList -Subnet 172.16.0.0/24 -Priority 1 
Add-VMMigrationNetwork -computername $ServerList -Subnet 172.16.1.0/24 -Priority 2 
Set-VMHost -ComputerName $ServerList -MaximumStorageMigrations 2 -MaximumVirtualMachineMigrations 2 -VirtualMachineMigrationPerformanceOption SMB -UseAnyNetworkForMigration $false 


#Enable S2D
Enable-ClusterStorageSpacesDirect  -CimSession $ClusterName -PoolFriendlyName $StoragePoolName -Confirm:0 

#Update Cluster Function Level

Update-ClusterFunctionalLevel -Cluster $ClusterName -Verbose -Force
Update-StoragePool -FriendlyName $StoragePoolName -Confirm:0


#Create S2D Tier and Volumes

Invoke-Command ($Node01) {
    #Create Storage Tier for Nested Resiliancy
New-StorageTier -StoragePoolFriendlyName $global:StoragePoolName -FriendlyName NestedMirror -ResiliencySettingName Mirror -MediaType HDD -NumberOfDataCopies 4 -ProvisioningType Thin

#Create Nested Mirror Volume
New-Volume -StoragePoolFriendlyName $global:StoragePoolName -FriendlyName Volume01-Thin -StorageTierFriendlyNames NestedMirror -StorageTierSizes 5GB -ProvisioningType Thin
}



############################################################Set Net-Intent on Node01########################################################
Invoke-Command ($Node01) {

#Remove-TempNetIntent
Remove-NetIntent -Name TempNSIntent

#North-South Net-Intents
Add-NetIntent -ClusterName $ClusterName -AdapterName "LOM Port 3", "LOM Port 4" -Name HCI -Compute -Management  

#Storage NetIntent
Add-NetIntent -ClusterName $ClusterName -AdapterName "LOM1 Port 1", "LOM1 Port 2"  -Name SMB -Storage
}


#########################################################################################################################################


############################################################Set Net-Intent on Node01########################################################
Invoke-Command ($Node02) {

#Remove-TempNetIntent
Remove-NetIntent -Name TempNSIntent

}

#########################################################################################################################################

#CAN'T SET THIN!!! 
Set-StoragePool -CimSession $ClusterName -FriendlyName $StoragePoolName -ResiliencySettingNameDefault Mirror  

#Configure for 21H2 Preview Channel
Invoke-Command ($ServerList) {
    Set-WSManQuickConfig -Force
    Enable-PSRemoting
    Set-NetFirewallRule -Group "@firewallapi.dll,-36751" -Profile Domain -Enabled true
    Set-PreviewChannel
}

Restart-Computer -ComputerName $ServerList -Protocol WSMan -Wait -For PowerShell -Force
#Pause for a bit - let changes apply before moving on...
sleep 180

#Enable CAU and update to latest 21H2 bits...
$CAURoleName="HCICLUS-CAU"
Add-CauClusterRole -ClusterName $ClusterName -MaxFailedNodes 0 -RequireAllNodesOnline -EnableFirewallRules -VirtualComputerObjectName $CAURoleName -Force -CauPluginName Microsoft.WindowsUpdatePlugin -MaxRetriesPerNode 3 -CauPluginArguments @{ 'IncludeRecommendedUpdates' = 'False' } -StartDate "3/2/2017 3:00:00 AM" -DaysOfWeek 4 -WeeksOfMonth @(3) -verbose
#Invoke-CauScan -ClusterName GBLRHSHCICLUS -CauPluginName "Microsoft.RollingUpgradePlugin" -CauPluginArguments @{'WuConnected'='true';} -Verbose | fl *
Invoke-CauRun -ClusterName $ClusterName -CauPluginName "Microsoft.RollingUpgradePlugin" -CauPluginArguments @{'WuConnected'='true';} -Verbose -EnableFirewallRules -Force



#Set Cloud Witness
Set-ClusterQuorum -Cluster $ClusterName -Credential $AADCred -CloudWitness -AccountName hciwitnessmcd  -AccessKey "lj7LGQrmkyDoMH2AnHXQjp8EI+gWMPsKDYmMBv1mL7Ldo0cwz+aYIoDA8fO3hJoSyY/fUksiOWlZ/8Heme1XGw=="


#Register Cluster with Azure
Invoke-Command ($Node01) {
    Connect-AzAccount -Credential $using:AADCred
    $armtoken = Get-AzAccessToken
    $graphtoken = Get-AzAccessToken -ResourceTypeName AadGraph
    Register-AzStackHCI -SubscriptionId $using:AzureSubID -ComputerName $using:Node01 -AccountId $using:AADAccount -ArmAccessToken $armtoken.Token -GraphAccessToken $graphtoken.Token -EnableAzureArcServer -Credential $using:ADCred 
}
############################################################################################################################################

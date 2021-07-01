###############################################################################
#The purpose of this script is to verify that the servers you are looking to configure as Azure Stack HCI cluster nodes have the appropriate outbound 
#connectivity needed to successfully register with Azure, deploy/register the AKS-HCI feature, download/update required PS modules, and register with the Arc RP. 
#If any of these tests fail, appropriate changes should be made to the network to allow the failed connectivity.
#
#
#This script assumes that Azure Stack HCI OS has been installed and updated.  The nodes should be members of the appropriate AD domain.  This script should be executed
#from the intended jumpbox/WAC server that will be used to configure and deploy the Azure Stack HCI cluster.  
#
# Modify the NODExx and ServerList variables below to map to the names of the target HCI nodes you are looking to deploy.
###############################################################################
#Set Name of Node01
$Node01 = "!!!NODE_NAME_HERE!!!"

#Set Name of Node02
$Node02 = "!!!NODE_NAME_HERE!!!"

#Set Name of Node02
$Node03 = "!!!NODE_NAME_HERE!!!"

#Set Name of Node02
$Node04 = "!!!NODE_NAME_HERE!!!"

#Set ServerList - if you have more (or less) nodes in your cluster, adjust this variable accordingly!
$ServerList = $Node01, $Node02, $Node03, $Node04
###############################################################################


[array]$endpoints443 = "secure.aadcdn.microsoftonline-p.com",` 
                    "aka.ms",` 
                    "dev.applicationinsights.io",` 
                    "www.azure.com",` 
                    "dev.azurefd.net",` 
                    "www.azure.net",` 
                    "management.azure-api.net",` 
                    "test.azuredatalakestore.net",` 
                    "test.azureedge.net",` 
                    "dev.loganalytics.io",` 
                    "www.microsoft.com",` 
                    "adminwebservice.microsoftonline.com",` 
                    "aadcdn.msauth.net",` 
                    "aadcdn.msftauth.net",` 
                    "act.trafficmanager.net",` 
                    "www.visualstudio.com",` 
                    "www.windows.net",` 
                    "aadwiki.windows-int.net",`  
                    "85b0613f-326f-448c-a4ec-55ef8a1538aa.agentsvc.eus.azure-automation.net",`  
                    "helm.sh",` 
                    "storage.googleapis.com",` 
                    "ecpacr.azurecr.io",` 
                    "www.powershellgallery.com",` 
                    "www.azurewebsites.net",` 
                    "az764295.vo.msecnd.net"
                    
[array]$endpoints80 = "secure.aadcdn.microsoftonline-p.com",` 
                    "aka.ms",` 
                    "dev.applicationinsights.io",` 
                    "www.azure.com",` 
                    "dev.azurefd.net",` 
                    "www.azure.net",` 
                    "management.azure-api.net",` 
                    "test.azureedge.net",` 
                    "dev.loganalytics.io",` 
                    "www.microsoft.com",` 
                    "adminwebservice.microsoftonline.com",` 
                    "aadcdn.msauth.net",` 
                    "aadcdn.msftauth.net",` 
                    "act.trafficmanager.net",` 
                    "www.visualstudio.com",` 
                    "www.windows.net",` 
                    "aadwiki.windows-int.net",` 
                    "download.windowsupdate.com",` 
                    "www.powershellgallery.com" 
                    
$endpoint9418 = "github.com"           
 
######Test outbound connection from the local jumpbox/WAC instance#####
#Test outbound connection for port 443 endpoints                    
foreach($endpoint in $endpoints443) {
    $Result = Test-NetConnection -ComputerName $endpoint -Port 443
    if ($Result.TcpTestSucceeded -eq $false) {
        Write-Host "Connection Test failed for" $endpoint "on port 443" -ForegroundColor Red
        Write-Host "Host = " $env:COMPUTERNAME -ForegroundColor Red
        Write-Host
         }
    }

#Test outbound connection for port 80 endpoints
foreach($endpoint in $endpoints80) {
    $Result = Test-NetConnection -ComputerName $endpoint -Port 80
     if ($Result.TcpTestSucceeded -eq $false) {
         Write-Host "Connection Test failed for" $endpoint "on port 80" -ForegroundColor Red
         Write-Host "Host = " $env:COMPUTERNAME -ForegroundColor Red
         Write-Host
         }
    }

#Test outbound connection for port 9418 endpoint.
$Result = Test-NetConnection -ComputerName $endpoint9418 -Port 9418
if ($Result.TcpTestSucceeded -eq $false) {
        Write-Host "Connection Test failed for" $endpoint "on port 9418" -ForegroundColor Red
        Write-Host "Host = " $env:COMPUTERNAME -ForegroundColor Red
        Write-Host
        }
#########################################################################

######Test outbound connection from each specified HCI node#####
#Test outbound connection for port 443 endpoints                    

Invoke-Command ($ServerList) {
    foreach($endpoint in $using:endpoints443) {
    $Result = Test-NetConnection -ComputerName $endpoint -Port 443
    if ($Result.TcpTestSucceeded -eq $false) {
         Write-Host "Connection Test failed for" $endpoint "on port 443" -ForegroundColor Red
         Write-Host "Host = " $env:COMPUTERNAME -ForegroundColor Red
         Write-Host         
         }
    }

    #Test outbound connection for port 80 endpoints
    foreach($endpoint in $using:endpoints80) {
        $Result = Test-NetConnection -ComputerName $endpoint -Port 80
         if ($Result.TcpTestSucceeded -eq $false) {
             Write-Host "Connection Test failed for" $endpoint "on port 80" -ForegroundColor Red
             Write-Host "Host = " $env:COMPUTERNAME -ForegroundColor Red
             Write-Host
             }
        }

    #Test outbound connection for port 9418 endpoint.
    $Result = Test-NetConnection -ComputerName $using:endpoint9418 -Port 9418
    if ($Result.TcpTestSucceeded -eq $false) {
            Write-Host "Connection Test failed for" $endpoint "on port 9418" -ForegroundColor Red
            Write-Host "Host = " $env:COMPUTERNAME -ForegroundColor Red
            Write-Host 
            }
	    } 

#########################################################################
Write-Host "TEST COMPLETE!"
pause




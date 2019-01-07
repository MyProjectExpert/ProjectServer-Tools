﻿<#
    .SYNOPSIS
        Walk thru creating IaaS SQL Server 2019
    .DESCRIPTION
        Create IaaS SQL Server VM
    .AUTHOR
        Michael Wharton
    .DATE
        01/04/2019
    .PARAMETER
        none - however update the constants below
    .EXAMPLE
        live demo
    .NOTES
        Make sure that AD VM is running
#>
$LoginRmAccount   = Login-AzureRmAccount   #  must log into Azure
# $adminUser        = "username"
# $adminPass        = "password"
# $secpass  = $adminPass |ConvertTo-SecureString -AsPlainText -Force
# $cred  = New-Object System.Management.Automation.PSCredential -ArgumentList $adminUser, $secPass
#
$cred = Import-CliXml -Path 'C:\safe\local-mawharton.txt’ 
#
$groupName        = "demosp"
$vmName           = "demosp"          #  using SharePoint 2019 trial as Active Directory
$storageName      = "demospstorage"   # NOTE: must be lowercase 
$OSDiskName       = "demospOS" 
$DataDiskName     = "demospdata1" 
$PIPname          = "demosppip"
$NICname          = "demospnic"
#
$DomainName       = "XXX2dev.local"        # using my demo AD
$vnetName         = "XXX2vnet"         # using my current VNET
$vnetGroupName    = "XXX2dev"          # from my resouce group
$SecurityGrp      = "XXX2Security"     # and security
#
$containerName    = "vhds"
$Location         = "East US 2"
$skuName          = "Standard_LRS"
$instanceSize     = "Standard_D2"
# Get-AzureRoleSize | where {$_.Cores -eq 2 -and $_.MemoryInMB -gt 4000 -and $_.MemoryInMB -lt 9000 } | select instance_size, rolesizelabel
$localIP          = "192.168.0.12"
# $publisherName  = "MicrosoftSQLServer"
# $offer          = "SQL2016-WS2016"
# $offer          = "SQL2017-WS2016"
# $offer          = "SQL2019-WS2016"
# $sku            = "SQLDEV"
$publisherName    = "MicrosoftSharePoint"
$offer            = "MicrosoftSharePointServer"
$sku              = "2019"
#
#Select-AzureSubscription -SubscriptionName $RmAccount.Context.Subscription.Name | Get-AzureNetworkSecurityGroup -Name $SecurityGrp
#Get-AzureNetworkSecurityGroup -Name $SecurityGrp -Profile
#
###############################################################################################################
#################### Create NEW Resource Group  ################################################
$grpExists = Get-AzureRmResourceGroup -Name $GroupName -ErrorAction SilentlyContinue
if ($grpExists)  
{
   Write-Host "  OK - Skip Creating Resource Group $GroupName  "  -BackgroundColor Green -ForegroundColor Blue
}
else
{
   Write-Host "  Create Resource Group $GroupName  "  -BackgroundColor Yellow  -ForegroundColor Blue
   New-AzureRmResourceGroup -ResourceGroupName $GroupName  -Location $Location -Verbose
}
###############################################################################################################
########### SQL Server Trial VM   ########################################################################
$vmExists = Get-AzureRmVM -VMName $vmName -ResourceGroupName $GroupName -ErrorAction SilentlyContinue
if ($vmExists)  
{
   Write-Host " Skipping - SQL Server VM $vmName already created "  -BackgroundColor Green -ForegroundColor Blue
}
else
{  # 13 minutes 25 seconds
   Measure-Command {
   Write-Host " Create SQL Server VM $vmName  "  -BackgroundColor Yellow -ForegroundColor Blue
###############################################################################################################
# Setup Storage for SharePoint 2019 VM ####################################################################################
$StorageAccount = New-AzureRmStorageAccount  `
    -ResourceGroupName $GroupName  -Location $Location `
    -Name $storageName -Sku Standard_LRS  -Verbose
 
# Get storage Content Keys
$storeKey  = (Get-AzureRmStorageAccountKey -ResourceGroupName $GroupName -Name $storageName)
$storeKey1 = (Get-AzureRmStorageAccountKey -ResourceGroupName $GroupName -Name $storageName).value[0]
$storeKey2 = (Get-AzureRmStorageAccountKey -ResourceGroupName $GroupName -Name $storageName).value[1]

# create Storage context and links to blob, table, queue, file, endpoints
$storeContext = New-AzureStorageContext -StorageAccountName $storageName -StorageAccountKey $storeKey1 -Verbose

# Create a storage container 
$container = New-azurestoragecontainer -name $containerName -Permission Container -Context $storeContext -Verbose
# Look at what was created
# Get-AzureStorageContainer -Context $storecontext

$StorageAccount   =  Get-AzureRmStorageAccount -ResourceGroupName $GroupName -Name $storageName
$OSDiskUri        = $StorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $OSDiskName + ".vhd"
$DataDiskUri      = $StorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $DataDiskName  + ".vhd"
###############################################################################################################
############# Create PIP Address or Public IP address for SharePoint Server VM #######################################
# Note: Get-module -ListAvailable  --- If prompt for Login-AzureRmAccount, it may be because multiple version of azure
$publicIP = New-AzureRmPublicIpAddress `
  -ResourceGroupName $GroupName  `
  -Location $Location `
  -AllocationMethod Static `
  -Name $PIPname -Verbose
###############################################################################################################
############## Create network interface card for SharePoint Server VM    #############################################
$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetGroupName -Name $vnetName   # using my VNET
$IPConfig = New-AzureRmNetworkInterfaceIpConfig -Name $NICname `
     -PrivateIpAddressVersion IPv4 -PrivateIpAddress $localIP `
     -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $publicIP.Id 
$NSG = Get-AzureRmNetworkSecurityGroup -Name $SecurityGrp -ResourceGroupName $vnetGroupName
$nic = New-AzureRmNetworkInterface -Name $NICname -ResourceGroupName $groupname `
     -Location $location -IpConfiguration $ipconfig -NetworkSecurityGroupId $nsg.Id 
###############################################################################################################
########### Create SharePoint 2019 Server virtual machine  ###########################################################
$vm = New-AzureRmVMConfig -VMName $vmName -VMSize $instanceSize |
    Set-AzureRmVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate  |
    Set-AzureRmVMSourceImage -PublisherName $PublisherName -Offer $offer -Skus $SKU -Version "latest"  |
    Set-AzureRmVMOSDisk     -Name $OSDiskName -VhdUri $OSDiskUri -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite |
    Add-AzureRmVMNetworkInterface -Id $nic.Id -Verbose 
#   Set-AzureRmVMDataDisk -VM $vm -Lun 0  -DiskSizeInGB 50 -Caching ReadWrite -Verbose
New-AzureRmVM -ResourceGroupName $GroupName -Location $Location -VM $vm -Verbose
    }
}
#
###############################################################################################################
######  RDP into new SharePoint 2019 server VM    ################################################################################
# Get-AzureRmPublicIpAddress -ResourceGroupName $GroupName  | Select IpAddress, name
$RDPIP = Get-AzureRmPublicIpAddress -ResourceGroupName $GroupName | WHERE {$_.Name -eq $PIPname} | Select IpAddress
mstsc /v:($RDPIP.IpAddress)
#  host   TrialSP2019
#  login  azurecloud/youraccount
#  Join   DEMO.LOCAL domain
#  reboot
#  OPEN PORT 443
#  Start SharPoint 2019 Server Wizard
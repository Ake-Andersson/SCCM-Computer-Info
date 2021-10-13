#CHANGE THESE VARIABLES TO TARGET SERVER, SITE AND CLIENT
$targetServer = "LabSRV02.test.lab.local"
$targetSite = "LL1"
$targetComputer = "LABPC01"
$outputPath = "Z:\SCCM_computer_info.txt"
#----------------------------------------------------------



#Function to get device and information
function getComputer {
    param(
        $SCCMsession,
        $computer
    )

    Invoke-Command -Session $SCCMsession -ScriptBlock {
        param(
            $computer
        )

        #Get device and information
        $gotComputer = Get-CMDevice -Name "$computer" | select Name,UserName,lastLogonUser,ADLastLogonTime,ADSiteName,DeviceOS,DeviceOSBuild,MACAddress,SMBIOSGUID,CNAccessMP,SiteCode,ClientCheckPass,IsActive,ClientVersion,LastActiveTime,LastPolicyRequest,LastStatusMessage
        return $gotComputer
    } -ArgumentList $computer
}


#Function to get collections and their deployments
function getCollections{
    param(
        $SCCMsession,
        $site,
        $computer
    )

    Invoke-Command -Session $SCCMsession -ScriptBlock {
        param(
            $site,
            $computer
        )

        #WMI query to select collections
        $collections = (Get-WmiObject -Namespace "root/SMS/site_$site" -Query "SELECT SMS_Collection.* FROM SMS_FullCollectionMembership, SMS_Collection where name = '$computer' and SMS_FullCollectionMembership.CollectionID = SMS_Collection.CollectionID").Name
        
        for($i=0; $i -lt $collections.Length; $i++){
            #get deployments for collection and add to output
            $deployment = Get-CMDeployment -CollectionName $collections[$i] | select ApplicationName, @{n="Type"; e={switch ($($_.featuretype)) { 1 {"Application"}; 2 {"Program"}; 3 {"MobileProgram"}; 4 {"Script"}; 5 {"SoftwareUpdate"} 6 {"Baseline"}; 7 {"TaskSequence"}; 8 {"ContentDistribution"}; 9 {"DistributionPointGroup"}; 10 {"DistributionPointHealth"}; 11 {"ConfigurationPolicy"}; 28 {"AbstractConfigurationItem"}}}}     

            #add deployment to collection if there is one
            if($deployment -ne $null){
                $collections[$i] = $collections[$i] + "%SPLIT%" + $deployment.ApplicationName + " (" + $deployment.Type + ")"
            }
        }

        return $collections
    } -ArgumentList $site,$computer
}

#Start session to target server
$session = New-PSSession -ComputerName $targetServer -ConfigurationName Microsoft.PowerShell32 -Authentication Kerberos

#Connect to site
Invoke-Command -Session $session -ScriptBlock {
    param(
        $site
    )

    Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"
    Set-Location $site":"
} -ArgumentList $targetSite

#Get information from functions
$computer = getComputer $session $targetComputer
$collections = getCollections $session $targetSite $targetComputer

#Add collections to computer object for easy output
$computer | Add-Member -MemberType NoteProperty -Name " " -Value " " #for linebreak in output
$computer | Add-Member -MemberType NoteProperty -Name "  " -Value " " #for linebreak in output
$computer | Add-Member -MemberType NoteProperty -Name "[COLLECTION]" -Value "[DEPLOYMENT]" #for linebreak in output
foreach($collection in $collections){
    if($collection -like "*%SPLIT%*"){
        $output = $collection -split "%SPLIT%"
        $computer | Add-Member -MemberType NoteProperty -Name $output[0] -Value $output[1]
    }else{
        $computer | Add-Member -MemberType NoteProperty -Name $collection -Value " "
    }
}

#Write to output file
$computer | Out-File -FilePath $outputPath

Remove-PSSession $session


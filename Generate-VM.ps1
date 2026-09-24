param (
    [string]$VMname = $( Read-Host "Input the name of the VM, please" )
 )

 function Get-VMconfig ($filePath)
{
    $ini = @{}
    switch -regex -file $FilePath
    {
        "^\[(.+)\]" # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        "^(;.*)$" # Comment
        {
            $value = $matches[1]
            $CommentCount = $CommentCount + 1
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value
        }
        "(.+?)\s*=(.*)" # Key
        {
            $name,$value = $matches[1..2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

$VMini = “E:\SourceFiles\$($VMname).ini”
$VMtemplate = "E:\VHDs\TMPL2019.vhdx"
$VMdiskpath = "F:\Virtual Disks\"
$VMvmpath = "F:\Virtual Machines\"
$VMunattend = "E:\SourceFiles\unattend.xml"
$VMgen = "1"
[int64]$VMram = 2GB
$VMswitch = "Production"

if ((!(Test-Path "$VMdiskpath$VMname.vhdx")) -And (!(Test-Path "$VMvmpath$VMname")))
{
    if (Test-Path “$VMini”)
    {
        $iniContent = Get-VMconfig “$VMini”
    }
    if ( $inicontent ) { if ( $iniContent[“HARDWARE”][“ram”] ) { [int64]$VMram = 1GB*$($iniContent[“HARDWARE”][“ram”]) } }
    if ( $inicontent ) { if ( $iniContent[“HARDWARE”][“template”] ) { $VMtemplate = "$($iniContent[“HARDWARE”][“template”])" } }
    if ( $inicontent ) { if ( $iniContent[“HARDWARE”][“diskpath”] ) { $VMdiskpath = "$($iniContent[“HARDWARE”][“diskpath”])" } }
    if ( $inicontent ) { if ( $iniContent[“HARDWARE”][“vmpath”] ) { $VMvmpath = "$($iniContent[“HARDWARE”][“vmpath”])" } }
    if ( $inicontent ) { if ( $iniContent[“HARDWARE”][“unattend”] ) { $VMunattend = "$($iniContent[“HARDWARE”][“unattend”])" } }
    if ( $inicontent ) { if ( $iniContent[“HARDWARE”][“gen”] ) { $VMgen = "$($iniContent[“HARDWARE”][“gen”])" } }
    if ( $inicontent ) { if ( $iniContent[“HARDWARE”][“switch”] ) { $VMswitch = "$($iniContent[“HARDWARE”][“switch”])" } }
    $VMini
    $VMtemplate
    $VMdiskpath
    $VMvmpath
    $VMunattend
    $VMgen
    $VMram
    $VMswitch
    Copy-Item -Path "$VMtemplate" -Destination "$VMdiskpath$VMname.vhdx" -Force
    $VHDLetter = (Mount-VHD -Path "$VMdiskpath$VMname.vhdx" -PassThru | Get-Disk | Get-Partition | where-object PartitionNumber -eq 2 | Get-Volume).DriveLetter
    Copy-Item -Path "$VMunattend" -Destination "$($VHDLetter):\Windows\Panther\"
    Dismount-VHD "$VMdiskpath$VMname.vhdx"
    New-VM -Name $VMname -Path "$VMvmpath" -NoVHD -Generation "$VMgen" -MemoryStartupBytes "$VMram" -SwitchName "$VMswitch"
    Add-VMHardDiskDrive -VMName $VMname -Path "$VMdiskpath$VMname.vhdx"
    # Upgrade VM
    [int64]$VMvcpu = $iniContent[“UPGRADES”][“vcpu”]
    [int64]$VMminram = 1GB*$iniContent[“UPGRADES”][“minram”]
    [int64]$VMmaxram = 1GB*$iniContent[“UPGRADES”][“maxram”]
    if ( $inicontent ) { if ( $inicontent[“UPGRADES”][“vcpu”] ) { Set-VM -Name $VMname -ProcessorCount $VMvcpu } }
    if ( $inicontent ) { if (( $inicontent[“UPGRADES”][“minram”] ) -And ( $iniContent[“UPGRADES”][“maxram”] )) { Set-VM -Name $VMname -DynamicMemory -MemoryMinimumBytes $VMminram -MemoryMaximumBytes $VMmaxram } }


    # Post-sysprep processing.
    Write-Host "Starting VM $VMname"
    Start-VM -Name $VMname
    if ($inicontent)
    {
        if ("$($inicontent['POSTCONFIG']['joindomain'])" -eq "yes") { 
        $cleartextpw = "Password1!"
        if ( $inicontent ) { if ( $iniContent[“POSTCONFIG”][“localpw”] ) { $cleartextpw = $iniContent[“POSTCONFIG”][“localpw”] } }
        $VMLocalUser = "Administrator"
        $VMLocalPWord = ConvertTo-SecureString -String "$cleartextpw" -AsPlainText -Force
        $VMLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $VMLocalUser, $VMLocalPWord
        while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”) {Sleep -Seconds 60}
	Write-Host "Invoking rename to $VMName"
        Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { param ($VMname); Rename-Computer $VMName -Restart } -ArgumentList $VMname
	Write-Host "Done renaming"
        do {Sleep -Seconds 120} while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”)
        $VMLocalUser = "$VMName\Administrator"
        $VMLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $VMLocalUser, $VMLocalPWord
        $VMdomainuser = "SEEYAY.CA\Administrator"
        $VMdomainpw = ("Password1!" | ConvertTo-SecureString -asPlainText -Force)
        $VMdomaincred = New-Object System.Management.Automation.PSCredential($VMdomainuser,$VMdomainpw)
	Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { Write-Host "Releasing IP"; ipconfig /release }
	Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { Write-Host "Setting DNS"; Get-NetAdapter | Set-DnsClientServerAddress -ServerAddresses "10.0.0.43" }
	Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { Write-Host "Renewing IP"; ipconfig /renew }
	Write-Host "Invoking domain join with local credentials"
        Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { param ($VMdomaincred); Write-Host "Invoking domain join with domain credentials"; Add-Computer -DomainName SEEYAY.CA -Credential $VMdomaincred -Restart } -ArgumentList $VMdomaincred
	Write-Host "Done with domain-join local credentials"
        do {Sleep -Seconds 60} while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”) 
        if ( $inicontent ) { if ( $iniContent[“POSTCONFIG”][“sw”] ) { $sw = $iniContent[“POSTCONFIG”][“sw”] } }
        if ( $inicontent ) { if ( $iniContent[“POSTCONFIG”][“sw”] ) { Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { Install-WindowsFeature NET-Framework-Features,NET-Framework-45-ASPNET,Web-Server,Web-App-Dev,Web-Mgmt-Tools -Restart } } }
        while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”) {Sleep -Seconds 60}
        } #end of if
     } #end of post sysprep
     #_____________________________________
     
     #PSGallery and xsmbshare
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
    Get-PSRepository
    
    $repository = Get-PSRepository -Name "PSGallery"
    if ($repository.InstallationPolicy -eq "Trusted") {
    Find-Module -Name XSMBShare | Install-Module -Force
    Import-Module XSMBShare -Force
    # Set the path to the source files directory and the name of the script
    $ScriptName = "exampleshare.ps1"
    cd E:\SourceFiles\
    
    # Compile the script
    . .\$scriptname

    exampleshare

    # Create the .mof file in the destination directory
    Start-DscConfiguration .\exampleshare -force 

    # Get the status of the DSC and test
    Get-DscConfigurationStatus
    
    }#end of psgallery and xsmbshare
    
    #_____________________________________________
    #disable IEESC
   Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}' -Name "IsInstalled" -Value 0
   Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}' -Name "IsInstalled" -Value 0
    #Enable firewall RDP
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    Write-Host "Remote Desktop is now enabled." 
    #__________________________________________________________________
    #IIS
    $scriptBlock = {
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools -Restart
    New-Item -ItemType Directory -Path 'C:\inetpub\wwwroot\Repo'
    New-WebVirtualDirectory -Site 'Default Web Site' -Name 'Repo' -PhysicalPath 'C:\inetpub\wwwroot\Repo' -force
    Copy-Item -Path '\\2515-Hyper-V\MyRepo\*' -Destination 'C:\inetpub\wwwroot\Repo\'
    Copy-Item -Path '\\2515-Hyper-V\MyRepo\*' -Destination 'C:\inetpub\wwwroot\Repo\'
    Set-WebConfigurationProperty -Filter "/system.webServer/security/access" -Name "sslFlags" -Value "None" -PSPath "IIS:\"
    #Firewall
    New-NetFirewallRule -DisplayName 'Allow HTTP Inbound' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -Enabled True -Profile Any
    New-NetFirewallRule -DisplayName 'Allow RDP Inbound' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Enabled True -Profile Any
    New-NetFirewallRule -DisplayName 'Block HTTPS Inbound' -Direction Inbound -Protocol TCP -LocalPort 443 -Action Block -Enabled True -Profile Any
    }

    Invoke-Command -ComputerName $vmname -ScriptBlock $scriptBlock
    
    #Test DSC
    Test-DscConfiguration .\ExampleShare


    }#end dont touch

else
{
    Write-Host "Source files exist that conflict with this request. Exiting..."
}


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
$VMtemplate = "E:\VHDs\TMPLG2-2019.vhdx"
$VMdiskpath = "F:\Virtual Disks\"
$VMvmpath = "F:\Virtual Machines\"
$VMunattend = "E:\SourceFiles\unattend.xml"
$VMgen = "2"
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
    Copy-Item -Path "$VMunattend" -Destination "G:\Windows\Panther\"
    Dismount-VHD "$VMdiskpath$VMname.vhdx"
    New-VM -Name $VMname -Path "$VMvmpath" -Generation "$VMgen" -MemoryStartupBytes "$VMram" -SwitchName "$VMswitch"
    Add-VMHardDiskDrive -VMName $VMname -Path "$VMdiskpath$VMname.vhdx"
    # Get VM firmware object data
Get-VMFirmware "$Vmname“
# Set the VM to use SecureBoot (or not)
Set-VMFirmware "$Vmname" -EnableSecureBoot On
# Set the VM boot order to DVD, Disk, NW
$firmware = Get-VMFirmware $VMname
$firmware.BootOrder
$hdd = $firmware.BootOrder[0]
$pxe = $firmware.BootOrder[1]
$dvd = $firmware.BootOrder[2]




    # Upgrade VM
    [int64]$VMvcpu = $iniContent[“UPGRADES”][“vcpu”]
    [int64]$VMminram = 1GB*$iniContent[“UPGRADES”][“minram”]
    [int64]$VMmaxram = 1GB*$iniContent[“UPGRADES”][“maxram”]
    if ( $inicontent ) { if ( $inicontent[“UPGRADES”][“vcpu”] ) { Set-VM -Name $VMname -ProcessorCount $VMvcpu } }
    if ( $inicontent ) { if (( $inicontent[“UPGRADES”][“minram”] ) -And ( $iniContent[“UPGRADES”][“maxram”] )) { Set-VM -Name $VMname -DynamicMemory -MemoryMinimumBytes $VMminram -MemoryMaximumBytes $VMmaxram } }


    # Post-sysprep processing.
    Start-VM -Name $VMname
    if ($inicontent)
    {
        if ("$($inicontent['POSTCONFIG']['joindomain'])" -eq "yes") { 
        $cleartextpw = "Password1@nait.ca"
        if ( $inicontent ) { if ( $iniContent[“POSTCONFIG”][“localpw”] ) { $cleartextpw = $iniContent[“POSTCONFIG”][“localpw”] } }
        $VMLocalUser = "Administrator"
        $VMLocalPWord = ConvertTo-SecureString -String "$cleartextpw" -AsPlainText -Force
        $VMLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $VMLocalUser, $VMLocalPWord
        while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”) {Sleep -Seconds 60}
        Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { param ($VMname); Rename-Computer $VMName -Restart } -ArgumentList $VMname
        do {Sleep -Seconds 120} while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”)
        $VMLocalUser = "$VMName\Administrator"
        $VMLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $VMLocalUser, $VMLocalPWord
        $VMdomainuser = "Cashcow.ca\Administrator"
        $VMdomainpw = ("Password1@nait.ca" | ConvertTo-SecureString -asPlainText -Force)
        $VMdomaincred = New-Object System.Management.Automation.PSCredential($VMdomainuser,$VMdomainpw)
        Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { param ($VMdomaincred); Add-Computer -DomainName Cashcow.ca -Credential $VMdomaincred -Restart } -ArgumentList $VMdomaincred
        do {Sleep -Seconds 60} while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”)
        if ( $inicontent ) { if ( $iniContent[“POSTCONFIG”][“sw”] ) { $sw = $iniContent[“POSTCONFIG”][“sw”] } }
        if ( $inicontent ) { if ( $iniContent[“POSTCONFIG”][“sw”] ) { Invoke-Command -VMName $VMName -Credential $VMLocalCredential -ScriptBlock { Install-WindowsFeature NET-Framework-Features,NET-Framework-45-ASPNET,Web-Server,Web-App-Dev,Web-Mgmt-Tools -Restart } } }
        while ((icm -VMName $VMName -Credential $VMLocalCredential {“Test”} -ea SilentlyContinue) -ne “Test”) {Sleep -Seconds 60}
        } 
     }
}
else
{
    Write-Host "Source files exist that conflict with this request. Exiting..."
}

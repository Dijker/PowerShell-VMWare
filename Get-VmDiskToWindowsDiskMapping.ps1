<# 

    Original script by Conrad (C-Rad): http://www.vnoob.com/2016/12/match-os-drive-letter-to-vm-disk-with-powercli/
    Modified by Petar Georgiev 2017-12-21

    * First connect to a vCenter using Connect-VIServer
    * $ComputerName should be VM's name (not VM object)
    * The script does not show mountpoints

    Typical usage:

    $vms = get-vm | ? { $_.PowerState -eq "PoweredOn" -and $_.Guest.Hostname -ilike "*.your.domain" -and $_.Guest.Nics -ne $null } | select -expand Name

    #// Export the list to CSV

    $vms | {path}\Get-VmDiskToWindowsDiskMapping | ConvertTo-Csv -NoTypeInformation | Out-File {path}\vms.disk.mappings.csv

    #// Output the list to a Grid

    $vms | {path}\Get-VmDiskToWindowsDiskMapping | Out-GridView

#>


[CmdletBinding()]
PARAM
(
    [Parameter(ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName
)

BEGIN {
    $ErrorActionPreference_old = $ErrorActionPreference
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
}


PROCESS {


    foreach ($Vm in $ComputerName) {

        $i=0
           
        try {

            $disks = Get-VM $Vm | Get-HardDisk -DiskType "RawPhysical","RawVirtual"
            
            $logtopart = Get-WmiObject -Class Win32_LogicalDiskToPartition -computername $Vm
            
            $disktopart = Get-WmiObject Win32_DiskDriveToDiskPartition -computername $Vm
            
            $logical = Get-WmiObject win32_logicaldisk -computername $Vm
            
            $volume = Get-WmiObject win32_volume -computername $Vm
            
            $partition = Get-WmiObject win32_diskpartition -computername $Vm        

            if (($VmView = Get-View -ViewType VirtualMachine -Filter @{"Name" = $Vm})) {
                
                $WinDisks = Get-WmiObject -Class Win32_DiskDrive -ComputerName $VmView.Name

                foreach ($VirtualSCSIController in ($VMView.Config.Hardware.Device | where {$_.DeviceInfo.Label -match "SCSI Controller"})) {
                    
                    foreach ($VirtualDiskDevice in ($VMView.Config.Hardware.Device | where {$_.ControllerKey -eq $VirtualSCSIController.Key})) {

                        $VirtualDisk = "" | Select ComputerName, SCSIController, DiskName, SCSI_Id, DiskFile, DiskSize, WindowsDisk, NAA, Drive, VolumeName, Error
                        $VirtualDisk.ComputerName = $Vm
                        $VirtualDisk.SCSIController = $VirtualSCSIController.DeviceInfo.Label
                        $VirtualDisk.DiskName = $VirtualDiskDevice.DeviceInfo.Label
                        $VirtualDisk.SCSI_Id = "$($VirtualSCSIController.BusNumber) : $($VirtualDiskDevice.UnitNumber)"
                        $VirtualDisk.DiskFile = $VirtualDiskDevice.Backing.FileName
                        $VirtualDisk.DiskSize = $VirtualDiskDevice.CapacityInKB * 1KB / 1GB
                        $VirtualDisk.NAA = $disks | ? {$_.name -like $VirtualDiskDevice.DeviceInfo.Label} | select -expand scsicanonicalname
                        $VirtualDisk.Error = ""
 
                        # Match disks based on SCSI ID
                        $DiskMatch = $WinDisks | ?{($_.SCSIPort -2 ) -eq $VirtualSCSIController.BusNumber -and $_.SCSITargetID -eq $VirtualDiskDevice.UnitNumber}
                        
                        if ($DiskMatch){
                            $VirtualDisk.WindowsDisk = "Disk $($DiskMatch.Index)"
                            $i++
                        } else {
                            throw  [Exception]"No matching Windows disk found for SCSI id $($VirtualDisk.SCSI_Id)"
                        }
             
                        $matchdisktopar = $disktopart|Where {$_.Antecedent -eq $diskmatch.__Path}
                        $matchlogtopart = $logtopart| Where {$_.Antecedent -eq $matchdisktopar.Dependent}
                        $logicalmatch = $logical| where {$_.path.path -eq $matchlogtopart.dependent}
                        $VirtualDisk.volumename = $logicalmatch.volumename
                        $VirtualDisk.drive = $logicalmatch.deviceid
 
 
                        $VirtualDisk
                    }
                }
            } else {
                throw [Exception]"VM $Vm Not Found"
            }
        } catch [Exception] {
            $VirtualDisk = "" | Select ComputerName, SCSIController, DiskName, SCSI_Id, DiskFile, DiskSize, WindowsDisk, NAA, Drive, VolumeName, Error
            $VirtualDisk.Computername = $Vm
            $VirtualDisk.Error = $_.Exception.Message
            $VirtualDisk
        }
    }
}

END {
    $ErrorActionPreference = $ErrorActionPreference_old
}

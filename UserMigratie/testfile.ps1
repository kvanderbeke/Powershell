<#
.SYNOPSIS
    This is a PowerShell template.

.DESCRIPTION
    This is a PowerShell template. This can be used to base other scripts on.
    If there are any problems with the script, please contact Orbid Servicedesk (servicedesk@orbid.be or + 32 9 272 99 00)

    This scripts creates a log file each time the script is executed.
    It deleted all the logs it created that are older than 30 days. This value is defined in the MaxAgeLogFiles variable.

.PARAMETER LogPath
    This defines the path of the logfile. By default: "C:\Windows\Temp\CustomScript\testfile.ps1.txt"
    You can overwrite this path by calling this script with parameter -logPath (see examples)

.EXAMPLE
    Use the default logpath without the use of the parameter logPath
    ..\testfile.ps1

.EXAMPLE
    Change the default logpath with the use of the parameter logPath
    ..\testfile.ps1 -logPath "C:\Windows\Temp\CustomScripts\Template.txt"

.NOTES
    File Name  : testfile.ps1
    Author     : Kristof Vanderbeke
    Company    : Orbid NV
#>

#region Parameters
#Define Parameter LogPath
param (
    $LogPath = "C:\Windows\Temp\CustomScripts\testfile.ps1.txt"
)
#endregion

#region variables
$MaxAgeLogFiles = 30

#region Log file creation
#Create Log file
Try {
    #Create log file based on logPath parameter followed by current date
    $date = Get-Date -Format yyyyMMddTHHmmss
    $date = $date.replace("/", "").replace(":", "")
    $logpath = $logpath.insert($logpath.IndexOf(".txt"), " $date")
    $logpath = $LogPath.Replace(" ", "")
    New-Item -Path $LogPath -ItemType File -Force -ErrorAction Stop

    #Delete all log files older than x days (specified in $MaxAgelogFiles variable)
    $limit = (Get-Date).AddDays(-$MaxAgeLogFiles)
    Get-ChildItem -Path $logPath.substring(0, $logpath.LastIndexOf("\")) -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $limit } | Remove-Item -Force

}
catch {
    #Throw error if creation of loge file fails
    $wshell = New-Object -ComObject Wscript.Shell
    $wshell.Popup($_.Exception.Message, 0, "Creation Of LogFile failed", 0x1)
    exit
}
#endregion

#region functions
#Define Log function
Function Write-Log {
    Param ([string]$logstring)

    $DateLog = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $WriteLine = $DateLog + "|" + $logstring
    try {
        Add-Content -Path $LogPath -Value $WriteLine -ErrorAction Stop
    }
    catch {
        Start-Sleep -Milliseconds 100
        Write-Log $logstring
    }
    Finally {
        Write-Host $logstring
    }
}
#endregion

#region Operational Script
Write-Log "[INFO] - Starting script"

Write-Log "[INFO] - Stopping script"
#endregion
$time = (Get-Date).AddMonths(-4)
$S = "DCBETS01", "DCBETS02", "DCBETS03", "DCBETS04", "DCBETS08"

ForEach ($Server in $S) {
    Get-WinEvent -ComputerName $server  -FilterHashtable @{logname = 'System'; ID = 7001; starttime = $time}
    foreach ($event in $events) {
        $event = [xml]$event[0].ToXml()
        $event.Event.EventData.Data
        $userSid = ($event.Event.EventData.Data | Where-Object {$_.name -eq "UserSid"})."#text"
        $userSid | Out-File c:\temp\usersDCBETSFARM.txt -Append
        #$user = Get-ADUser -Server SBE001.bektex.local -Identity $userSid -Properties *
        #Write-Host $user.name | Out-File c:\temp\users.txt -Append
    }
}

$csv = import-csv C:\temp\users2.txt

foreach ($line in $csv) {
    $user = Get-ADUser -Server SBE001.bektex.local -Identity $line.SID -Properties *
    $user.name | Out-File c:\temp\usersDCBETSFARM.txt -Append
}
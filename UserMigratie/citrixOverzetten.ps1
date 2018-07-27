#Logging definieren
function LogWrite
{
    Param ([string]$logstring)
    $DateLog = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $WriteLine = $DateLog + " " + $logstring
    try{
        Add-Content -Path $FullLog -Value $WriteLine -ErrorAction Stop
    } catch {
        Start-Sleep -Milliseconds 100
        LogWrite $logstring
    }
}

#Variabelen voor Logging
$LogPath = "C:\Windows\Temp"
$LogName = "ConvertCitrixUsers.log"
$FullLog = $LogPath + "\" + $LogName

if (Test-Path -Path $FullLog)
{
}
else
{
    New-Item -Path $FullLog -ItemType File -Force
}

#functie om Citrix groepen over te zetten
function memberOf($gebruikersnaam,$oldGroup,$newGroup){
    $server = "domctrl01"
    $gebruikersnaam = $gebruikersnaam.toUpper()
    $member = (Get-ADGroupMember -Identity $oldGroup -Server $server) | Select-Object -ExpandProperty samAccountName
    if ($member.Contains($gebruikersnaam))
    {
        LogWrite "$gebruikersnaam is lid van $oldGroup"
        Add-ADGroupMember $newGroup $gebruikersnaam -Server $server -Confirm:$False
        Remove-ADGroupMember $oldGroup $gebruikersnaam -Server $server -Confirm:$False
    }
    else
    {
        LogWrite "$gebruikersnaam is geen lid van $oldGroup"
    }
}

$server = "domctrl01"

Write-Host "Logfile wordt weggeschreven naar $($FullLog)"
$username = Read-Host "Gelieve gebruikersnaam die moet overgezet worden naar nieuwe Citrix in te geven"


if (Get-ADUser $username){
        memberof $username 'CTX_PRD_APP_BIZAGI' 'CTX_PRD_XA7X_APP_BIZAGI'
        memberof $username 'CTX_PRD_APP_CAREPLUS' 'CTX_PRD_XA7X_APP_CAREPLUS'
        memberof $username 'CTX_PRD_APP_CRM' 'CTX_PRD_XA7X_APP_CRM'
        memberof $username 'CTX_PRD_APP_DEFAULT_APPLICATIONS' 'CTX_PRD_XA7X_APP_DEFAULT_APPLICATIONS'
        memberof $username 'CTX_PRD_APP_DESKTOP' 'CTX_PRD_XA7X_APP_DESKTOP'
        memberof $username 'CTX_PRD_APP_DPLANAID' 'CTX_PRD_XA7X_APP_DPLANAID'
        memberof $username 'CTX_PRD_APP_EF_FRAP' 'CTX_PRD_XA7X_APP_EF_FRAP'
        memberof $username 'CTX_PRD_APP_FINACC' 'CTX_PRD_XA7X_APP_FINACC'
        memberof $username 'CTX_PRD_APP_FINACC_URL' 'CTX_PRD_XA7X_APP_FINACC_URL'
        memberof $username 'CTX_PRD_APP_FLOWCHART' 'CTX_PRD_XA7X_APP_FLOWCHART'
        memberof $username 'CTX_PRD_APP_INTRAWEB' 'CTX_PRD_XA7X_APP_INTRAWEB'
        memberof $username 'CTX_PRD_APP_IRIS_APPL_IT' 'CTX_PRD_XA7X_APP_IRIS_APPL_IT'
        memberof $username 'CTX_PRD_APP_MS_ACCESS' 'CTX_PRD_XA7X_APP_MS_ACCESS'
        memberof $username 'CTX_PRD_APP_MS_COMMAND_PROMPT' 'CTX_PRD_XA7X_APP_MS_COMMAND_PROMPT'
        memberof $username 'CTX_PRD_APP_MS_OUTLOOK' 'CTX_PRD_XA7X_APP_MS_OUTLOOK'
        memberof $username 'CTX_PRD_APP_MS_REMOTE_DESKTOP_CLIENT' 'CTX_PRD_XA7X_APP_MS_REMOTE_DESKTOP_CLIENT'
        memberof $username 'CTX_PRD_APP_MS_TELNET' 'CTX_PRD_XA7X_APP_MS_TELNET'
        memberof $username 'CTX_PRD_APP_ORBIS_DOSSIER' 'CTX_PRD_XA7X_APP_ORBIS_DOSSIER'
        memberof $username 'CTX_PRD_APP_ORBIS_UURROOSTER' 'CTX_PRD_XA7X_APP_ORBIS_UURROOSTER'
        memberof $username 'CTX_PRD_APP_PROTEAM' 'CTX_PRD_XA7X_APP_PROTEAM'
        memberof $username 'CTX_PRD_APP_PROTIME' 'CTX_PRD_XA7X_APP_PROTIME'
        memberof $username 'CTX_PRD_APP_VIVALDI_2FLOW' 'CTX_PRD_XA7X_APP_VIVALDI_2FLOW'
        memberof $username 'CTX_PRD_BR_SET_DEFAULT_PRINTER' 'CTX_PRD_XA7X_SET_DEFAULT_PRINTER'
        memberof $username 'CTX_PRD_SET_ALLOW_CLIENT_DRIVES_ALL' 'CTX_PRD_XA7X_SET_ALLOW_CLIENT_DRIVES_ALL'
    }
else{
    Logwrite "username niet gevonden"
    LogWrite $Error[0].Exception.Message
}


try{

    $user = Get-ADUser $username -Properties *

    try{
    $string = Select-String -Path "\\waak.local\SYSVOL\waak.local\scripts\$($user.scriptPath)" -Pattern "addprinter"  | Select-Object Line
    $string = $string.Line

    $string = $string.ToString()
    $printscript = $string.Substring(8)

        try{
            (Get-Content $printscript).ToLower() | ForEach-Object {
                $_.replace('printprdvs01', 'printprdvs03') }| Set-Content "\\fileserver\loginscript\printers\$($username)_addprinter.vbs"

            LogWrite "Printscript gekopieerd"
            }
            catch{
                LogWrite "Probleem bij het aanpassen van het printscript"
                LogWrite $Error[0].Exception.Message
            }
    }
    catch{
         LogWrite "Probleem bij het ophalen van het printscript"
         LogWrite $Error[0].Exception.Message
    }
}
catch{
    LogWrite "Probleem bij het aanpassen van het printscript"
    LogWrite $Error[0].Exception.Message
}

try{
    Move-ADObject -Identity $user -TargetPath "OU=Standaard_Gebruikers,OU=Gebruikers,OU=WAAK - Productie,DC=waak,DC=local" -PassThru -Server $server
    LogWrite "Gebruiker verplaatst naar OU=Standaard_Gebruikers,OU=Gebruikers,OU=WAAK - Productie,DC=waak,DC=local"
    }
catch{
    LogWrite "Probleem bij verplaatsen gebruiker"
    LogWrite $Error[0].Exception.Message
    }


finally{
    Write-Host "Script uitgevoerd. Kijk in de logfile voor eventuele fouten"
}

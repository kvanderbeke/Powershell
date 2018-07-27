<#
.SYNOPSIS
Dit script gaat een user van de oude naming convention geautomatiseerd overzetten naar de nieuwe naming convention.

.DESCRIPTION
Dit script gaat op basis van een CSV file gevuld met oude gebruikersnamen nieuwe namen aanmaken. Het script gaat hiervoor een nieuwe user aanmaken met dezelfde attributen als de
huidige gebruiker, een nieuw login- en printscript aanmaken, de mailbox loskoppelen en aan de nieuwe gebruiker hangen, de oude gebruiker archiveren, de nieuwe gebruiker toevoegen aan
de correcte nieuwe Citrix groepen, de oude loginscripts archiveren en emails sturen naar de mensen die nog een manuele actie dienen te ondernemen.

.EXAMPLE
Voer het script uit vanuit powershell ISE en vul de nodige gevraagde parameters in. Hierna verloopt het verdere proces geautomatiseerd.

.NOTES
Dit script moet uitgevoerd worden vanaf een gebruiker met de nodige rechten voor Active Directory. Zonder deze rechten loopt het script fout. Credentials die in het begin gevraagd worden
dienen voldoende rechten te hebben op de Exchange omgeving. Dit script staat lokaal op de server die de scheduled task loopt. (domctrl01)


File Name  : renameExistingUserTask.ps1  
Author     : Kristof Vanderbeke  
Company    : Orbid NV


#>

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
$LogName = "RenameExistingUserTask.log"
$FullLog = $LogPath + "\" + $LogName

if (Test-Path -Path $FullLog)
{
}
else
{
    New-Item -Path $FullLog -ItemType File -Force
}


#functie om speciale tekens uit naam te verwijderen
function Remove-StringLatinCharacters
{
    PARAM ([string]$String)
    [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
}

#functie om Citrix groepen over te zetten
function memberOf($gebruikersnaam,$oldGroup,$newGroup){
    $server = "domctrl01"
    $gebruikersnaam = $gebruikersnaam.toUpper()
    $member = (Get-ADGroupMember -Identity $oldGroup -Server $server) | select -ExpandProperty samAccountName
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

#kijken of gebruiker lid is van specifieke groep
function lidVan($gebruikersnaam,$groep){
    $server = "domctrl01"
    $gebruikersnaam = $gebruikersnaam.toUpper()
    $member = (Get-ADGroupMember -Identity $groep -Server $server) | select -ExpandProperty samAccountName
    if ($member.Contains($gebruikersnaam))
    {
        Write-Host "$gebruikersnaam is lid van $groep"
        #Remove-ADGroupMember $groep $gebruikersnaam -Server $server -Confirm:$False
        Return $true
    }
    else
    {
        Write-Host "$gebruikersnaam is geen lid van $oldGroup"
        Return $false
    }
}


#region Exchange connectie leggen
try{
    $pass = cat C:\securestring.txt | convertto-securestring
    $UserCredential = new-object -typename System.Management.Automation.PSCredential -argumentlist “waak\admin_orbid”,$pass
    #$UserCredential = $Host.ui.PromptForCredential("Gegevens nodig voor Exchange connectie", "Gelieve een Exchange admin op te geven.", "", "NetBiosUserName")
    #$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://exchvs01.waak.local/PowerShell/ -Authentication Kerberos
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://exchvs02.waak.local/PowerShell/ -Authentication Kerberos -Credential $UserCredential
    Import-PSSession $Session
}
catch{
    LogWrite "Fout bij het verbinden met Exchange. Script sluit zichzelf af"
    throw "Fout bij het verbinden met Exchange. Script sluit zichzelf af"
}
#endregion

#variabelen
$server = 'DOMCTRL01'
$From = "servicedesk.ICT@waak.be"
$SMTPServer = "exchange.waak.local"
$SMTPPort = "25"
$encoding = [System.Text.Encoding]::UTF8

#Kiezen van locatie voor CSV bestand
#Opbouw CSV
#titel Users
#Eronder alle gebruikersnamen die moeten overgezet worden
Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "CSV (*.csv)| *.csv"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

try{
    #$inputfile = Get-FileName "\\fileserver\Iva\Scripts"
    $UserList = Import-Csv "\\fileserver\Iva\Scripts\usersOld.csv"
}
catch{
    LogWrite "Geen bestand ingegeven voor gebruikers. Script sluit zichzelf af"
    throw "Geen bestand ingegeven voor gebruikers. Script sluit zichzelf af"
}

foreach ($oldUser in $UserList)
{
    try{
        #ophalen oude gebruiker om voor en achternaam te weten
        $user = Get-ADUser $oldUser.users -Properties * -Server $server
    
        $firstName = Remove-StringLatinCharacters -String $user.GivenName
        $lastName = Remove-StringLatinCharacters -String $user.sn

        $completedFirstName = $false
        $completedLastName = $false
        $retrycount = 0
    }
    catch{
        LogWrite "Fout bij het ophalen van de oude gebruiker"
        Throw "Fout bij het ophalen van de oude gebruiker"
    }
    try{

#region aanvullen voornaam indien deze minder dan 4 letters bevat
        while (-not $completedFirstName){
            try {
                $firstName = $firstName -replace '\s',''
                $firstname = $firstName.subString(0, 4) 
                $completedFirstName = $true
            }
            catch [ArgumentOutOfRangeException] {
                 $firstName = $firstName + '_'
            }
        }
#endregion

#region aanvullen achternaam indien deze minder dan 4 letters bevat
        while (-not $completedLastName){
            try {
                $lastname = $lastname -replace '\s',''
                $lastname = $lastName.subString(0, 4) 
                $completedLastName = $true
            }
            catch [ArgumentOutOfRangeException] {
                $lastName = $lastName + '_'
            }
        }
     }
    catch{
        LogWrite "Probleem bij het aanvullen van de gebruikersnaam voor iemand met korte naam"
        Throw "Probleem bij het aanvullen van de gebruikersnaam voor iemand met korte naam"
    }
#endregion

#aanmaken gebruikersnaam door voor- en achternaam te combineren in hoofdletters
    try{
        $Username = $($firstName + $lastName).ToUpper()
        LogWrite "$Username zal aangemaakt worden"
    }
    catch{
        LogWrite "Fout bij het aanmaken van de gebruikersnaam"
        Throw "Fout bij het aanmaken van de gebruikersnaam"
    }
    

#region Username Checken 
#controleren of gebruikersnaam reeds bestaat
#als deze reeds bestaat laatste letter verwijderen en vervangen door 1-9

    try{
        if (Get-ADUser -Filter "SamAccountName -eq '$Username'" -Server $server){
            LogWrite "Gebruikersnaam $username is reeds in gebruik"

            $i = 1 
            while ($i -lt 9) { 
                $i +=1 
                if (Get-ADUser -Filter "SamAccountName -eq '$($Username.subString(0,7) +$i)'" -Server $server){ 
                    LogWrite "Gebruikersnaam $($Username.subString(0,7) +$i) is reeds in gebruik." 
                } 
                else {break} 
            } 
            LogWrite "Gebruikersnaam $($Username.subString(0,7) +$i) is beschikbaar"
            $Username =  $($Username.subString(0,7) +$i)
        }
        else{
            LogWrite "$Username is beschikbaar." 
        }
    }
    catch{
        LogWrite "Fout bij het controleren of de gebruikersnaam nog beschikbaar is"
        Throw "Fout bij het controleren of de gebruikersnaam nog beschikbaar is"
    }
#endregion

#region aanmaken gebruiker
#effectief aanmaken van de gebruiker op basis van de aangemaakte gebruikersnaam
    try{
    #ophalen loginscript en printscript van oude gebruiker
        $loginscript = Get-Childitem –Path "\\waak.local\SYSVOL\waak.local\scripts\$($user.scriptPath)" -File -Recurse -ErrorAction SilentlyContinue
        $pos = $loginscript.Name.IndexOf("_")
        $leftPart = $loginscript.Name.Substring(0, $pos)
        $rightPart = $loginscript.Name.Substring($pos+1)
        $scriptPath = $($leftPart+ "_" + $username +".bat")

        $string = Select-String -Path "\\waak.local\SYSVOL\waak.local\scripts\$($user.scriptPath)" -Pattern "addprinter"  | Select-Object Line
        $string = $string.Line

        $string = $string.ToString()
        $printscript = $string.Substring(8)

        #Copy-Item $printscript "\\fileserver\loginscript\printers\$($username)_addprinter.vbs"
        #Copy-Item $loginscript.PSPath "\\waak.local\SYSVOL\waak.local\scripts\$scriptPath"
        (Get-Content $printscript).ToLower() | ForEach-Object {
            $_.replace('printprdvs01', 'printprdvs03').replace("$($user.samAccountName.ToLower())", "$($username)") }| Set-Content "\\fileserver\loginscript\printers\$($username)_addprinter.vbs"
        LogWrite "Printscript gekopieerd"
        (Get-Content $loginscript.PSPath).ToLower().Replace("$($user.SamAccountName.ToLower())","$username") | Set-Content "\\waak.local\SYSVOL\waak.local\scripts\$scriptPath"
        LogWrite "Loginscript gekopieerd"


    }
    catch{
        LogWrite "Probleem bij het aanpassen van het loginscript van de gebruiker. Gelieve deze zelf te kopieren"
    }

    try{
    #proberen effectief aanmaken gebruiker
        if($user.otherTelephone){
            New-ADUser -SamAccountName $username -UserPrincipalName "$($username)@waak.be" -GivenName $user.GivenName -Surname $user.sn `
            -DisplayName ($user.sn + " " + $user.GivenName) -Name ($user.sn + " " + $user.GivenName) -AccountPassword (ConvertTo-SecureString -AsPlainText "azerty" -Force) `
            -Enabled $true -PasswordNeverExpires $false -ChangePasswordAtLogon $true -Initials ($user.GivenName.Substring(0,1) + $user.sn.Substring(0,1)) `
            -Path "OU=Standaard_Gebruikers,OU=Gebruikers,OU=WAAK - Productie,DC=waak,DC=local" -OfficePhone $user.OfficePhone -Description $user.Description `
            -Fax $user.Fax -Department $user.Department -Company $user.Company -Manager $user.Manager -Title $user.Title  -OtherAttributes @{'otherTelephone'=$($user.otherTelephone)} `
            -ScriptPath $scriptPath -Server $server
        }
        Else{
            New-ADUser -SamAccountName $username -UserPrincipalName "$($username)@waak.be" -GivenName $user.GivenName -Surname $user.sn `
            -DisplayName ($user.sn + " " + $user.GivenName) -Name ($user.sn + " " + $user.GivenName) -AccountPassword (ConvertTo-SecureString -AsPlainText "azerty" -Force) `
            -Enabled $true -PasswordNeverExpires $false -ChangePasswordAtLogon $true -Initials ($user.GivenName.Substring(0,1) + $user.sn.Substring(0,1)) `
            -Path "OU=Standaard_Gebruikers,OU=Gebruikers,OU=WAAK - Productie,DC=waak,DC=local" -OfficePhone $user.OfficePhone -Description $user.Description `
            -Fax $user.Fax -Department $user.Department -Company $user.Company -Manager $user.Manager -Title $user.Title -ScriptPath $scriptPath -Server $server
        }
        LogWrite "Gebruiker aangemaakt"
    }
    catch{
        LogWrite "Er was een probleem bij het aanmaken van de gebruiker"
        Throw "Er was een probleem bij het aanmaken van de gebruiker"
    }

    #kopieren van groepen naar de nieuwe gebruiker
    Get-ADPrincipalGroupMembership -Identity $user -Server $server | % {Add-ADPrincipalGroupMembership -Identity $Username -MemberOf $_ -Server $server}
    LogWrite "Groepen van gebruiker gekopieerd"
    Add-ADGroupMember 'G_Homes' $username -Confirm:$False -Server $server
    
#endregion

#region accessrechten overzetten naar nieuwe gebruiker
$mailboxRechten = Get-Mailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited | Get-MailboxPermission -User $user

#endregion

#region Mailbox
#loskoppelen mailbox oude gebruiker om aan nieuwe te hangen
#aliasen overplaatsen
#activesync toestellen ophalen

    #ophalen mailboxdatabase van oude gebruiker - nieuwe gebruiker komt op dezelfde DB
    try{
        #Get-MailboxDatabase | Clean-MailboxDatabase
        $DB = (Get-mailbox -identity "$($user.samAccountName)" | Select database).Database
    }
    catch{
        LogWrite "Er was een probleem bij ophalen van de mailboxdatabase van de gebruiker"
    }

#region ophalen activesync toestellen
    #ophalen activesync toestellen zodat we weten of de gebruiker zijn emails op een mobiel toestel leest
    try{
        $devices = Get-ActiveSyncDevice -Mailbox $user.name
        foreach($device in $devices){
            if($device.FriendlyName -ne $null){
                $to = "aanvraag_bpm_ict@waak.be"
                $Subject = "Smartphone van gebruiker $($user.displayname) moet overgezet worden naar nieuw mailadres"
                $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag ICT</p>

<p>Zonet werd gebruiker $($username) aangemaakt voor $($user.givenName) $($user.sn) ter vervanging van de oude account $($user.samAccountName).<br>
Hiervoor moet zijn smartphone(s) $($device.FriendlyName) opnieuw ingesteld worden.</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
                Send-MailMessage -From $From -to $to -Subject $Subject -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
                LogWrite "Email gestuurd naar aanvraag BPM-ICT voor configuratie smartphone"
            }
        }
    }
    catch{
        LogWrite "Probleem bij het ophalen van activeSync toestellen"
    }
#endregion

#region ophalen proxy adressen gebruiker + FAX
    try{
        $proxy = @()
        $addresses = $user.proxyAddresses
        ForEach ($Address In $addresses)
        {
            if (($Address -cmatch "SMTP:") -or ($Address -cmatch "X400:")) {
            }
            elseif  ($Address -cmatch "DIR:"){
                $to = "steven.moerman@waak.be"
                $Subject = "Faxaccount voor $($username) moet worden aangepast"
                $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Beste</p>

<p>Zonet werd gebruiker $($username) aangemaakt voor $($user.givenName) $($user.sn) ter vervanging van de oude account $($user.samAccountName).<br>
Hiervoor moet het nummer van de Fax $($address)) nog aangepast worden.</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
                Send-MailMessage -From $From -to $to -Subject $Subject -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
                LogWrite "Email gestuurd naar Steven Moerman voor het aanpassen van de Faxaccount"
            }
            else{
                $proxy += $Address.toString()
            }
        }
    }
    catch{
        LogWrite "Probleem bij het ophalen van de proxyadressen van de oude gebruiker"
    }
#endregion
    
    try{
        #disable oude mailbox gebruiker
        Disable-Mailbox $user.SamAccountName -Confirm:$false 
        Start-Sleep 10
        Get-MailboxStatistics -Database $db | ForEach {Update-StoreMailboxState -Database $db -Identity $_.MailboxGuid -Confirm:$False}
        #Get-MailboxDatabase | Clean-MailboxDatabase
        LogWrite "Oude mailbox disabled"

        #mailbox verbinden met nieuwe gebruiker
        Connect-Mailbox -Identity $user.name -User $Username -Database $DB -Alias $Username
        #Get-MailboxDatabase | Clean-MailboxDatabase
        Get-MailboxStatistics -Database $db | ForEach {Update-StoreMailboxState -Database $db -Identity $_.MailboxGuid -Confirm:$False}
        Start-Sleep 10
        Set-Mailbox -Identity $Username -EmailAddressPolicyEnabled $false
        LogWrite "Nieuwe mailbox enabled"

        #Oracle full access geven op mailbox
        Get-Mailbox $username | Add-MailboxPermission -User oracle -AccessRights FullAccess -InheritanceType All

        #adressen van oude gebruikers overzetten naar nieuwe gebruiker
        ForEach($email in $proxy){
            Set-ADUser $username -Add @{Proxyaddresses="$email"} -Server $server
        }

        Set-ADUser $user -Clear legacyExchangeDN -Server $server
        LogWrite "Emailadressen gekopieerd"

        foreach ($identity in $mailboxRechten){
            Add-MailboxPermission -User $username -AccessRights $identity.AccessRights -Identity $identity.Identity
            Write-Host $identity.AccessRights
        }
    }
    catch{
        LogWrite "probleem bij het afkoppelen/verbinden van de mailbox"
    }
#endregion

#region emails sturen
#region Protime
    $to = "jan.lewylle@waak.be"
    $cc = "BPM@waak.be"
   
    $toEric = "eric.bonne@waak.be"
    $Subject = "Nieuwe gebruiker $($username) aangemaakt"
    $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag Jan</p>

<p>Zonet werd gebruiker $($username) aangemaakt voor $($user.givenName) $($user.sn) ter vervanging van de oude account $($user.samAccountName).<br>
Is het mogelijk om hiervoor in Protime het nodige te doen?</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
    Send-MailMessage -From $From -to $to -Cc $cc -Subject $Subject -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
    LogWrite "Email gestuurd naar Jan Lewylle"
#endregion
#region Vivaldi
    $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag Eric</p>

<p>Zonet werd gebruiker $($username) aangemaakt voor $($user.givenName) $($user.sn) ter vervanging van de oude account $($user.samAccountName).<br>
Is het mogelijk om hiervoor in Vivaldi het nodige te doen?</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
    Send-MailMessage -From $From -to $toEric -Subject $Subject -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
    LogWrite "Email gestuurd naar Eric Bonne"
#endregion
#region IRIS
    $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag Eric</p>

<p>Zonet werd gebruiker $($username) aangemaakt voor $($user.givenName) $($user.sn) ter vervanging van de oude account $($user.samAccountName).<br>
Is het mogelijk om hiervoor in IRIS het nodige te doen?</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
    Send-MailMessage -From $From -to $toEric -Subject $Subject -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
    LogWrite "Email gestuurd naar Eric Bonne"
#endregion
#region Einvoice
if (lidVan $user.SamAccountName "G_EINVOICE"){
    $SubjectEinvoice = "Nieuwe gebruiker $($username) aangemaakt in Einvoice"
    $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag Eric</p>

<p>Zonet werd gebruiker $($username) aangemaakt voor $($user.givenName) $($user.sn) ter vervanging van de oude account $($user.samAccountName).<br>
Is het mogelijk om hiervoor in Einvoice het nodige te doen?</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
    Send-MailMessage -From $From -to $toEric -Subject $SubjectEinvoice -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
    Remove-ADGroupMember "G_EINVOICE" $user.SamAccountName -Server $server -Confirm:$False
    LogWrite "Email gestuurd naar Eric Bonne voor Einvoice"
    }
    else{
    LogWrite "Gebruiker zat niet in de Einvoice groep"
    }
#endregion
#region CRM
if (lidVan $user.SamAccountName "G_CRM"){
    $SubjectCRM = "Nieuwe gebruiker $($username) aangemaakt met CRM"
    $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag Eric</p>

<p>Zonet werd gebruiker $($username) aangemaakt voor $($user.givenName) $($user.sn) ter vervanging van de oude account $($user.samAccountName).<br>
Is het mogelijk om hiervoor in CRM het nodige te doen?</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
    Send-MailMessage -From $From -to $toEric -Subject $SubjectCRM -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
    LogWrite "Email gestuurd naar Eric Bonne voor CRM"
    }
    else{
    LogWrite "Gebruiker zat niet in de  CRM groep"
    }
#endregion      

    
#endregion

#citrix groepen in orde brengen

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

#ACL op persoonlijke map goedzetten
try{
    #Afdeling loginscript ophalen
    $algemeenScript = "$($leftPart).bat"
    $afdelingsMap = Select-String -Path "\\waak.local\SYSVOL\waak.local\scripts\$algemeenscript" -Pattern "net use N:"  | Select-Object Line
    $afdelingsMap = $afdelingsMap.Line
    #eerste 11 karakters weglaten zodat we kunnen beginnen met \\fileserver
    $afdelingsMap = $afdelingsMap.ToString()
    $afdelingsMap = $afdelingsMap.Substring(11)


    #laatste 3 letters laten wegvallen zodat enkel FQDN overblijft
    $afdelingsMap = $afdelingsMap.Substring(0,$afdelingsMap.Length-3)
    $afdelingsMap = $afdelingsMap + "\"

    $path = "$($afdelingsMap)$($user.SamAccountName)"
    Logwrite "Pad van persoonlijke map is $($path)"

    try{
        if (Test-Path $path){
            $acl = Get-Acl -Path $path 
            $rights = $acl | Select-Object -ExpandProperty Access | Where-Object identityreference -eq "WAAK\$($user.SamAccountName)"
            $newAcl = New-Object System.Security.AccessControl.FileSystemAccessRule("WAAK\$($userName)",$rights.FileSystemRights.ToString(),$rights.InheritanceFlags.ToString(),$rights.PropagationFlags.ToString(),$rights.AccessControlType.ToString())
            $acl.SetAccessRule($newAcl)
            Set-Acl -path $path $acl
            LogWrite "Rechten goedgeplaatst op map $($path) voor gebruiker $($username)"
        }
        else{
        }
    }
    catch{
        LogWrite "Probleem met ACL ophalen/wegschrijven, had gebruiker wel persoonlijke map met eigen rechten op?"
    }
}
catch{
    LogWrite "Probleem met pad ophalen van persoonlijke map"
}

#Disable AD account old user
    try{
        Move-ADObject -Identity $user -TargetPath "OU=Disabled_Gebruikers,OU=Gebruikers,OU=WAAK - Productie,DC=waak,DC=local" -PassThru -Server $server
        Disable-ADAccount -Identity $user.SamAccountName -Server $server
    }
    catch{
        LogWrite "Probleem bij uitschakelen oude gebruikersaccount"
        }

#Scripts van oude gebruiker verplaatsen naar archief
    if ($user.ScriptPath){
        try{
            Move-Item -Path $loginscript.PSPath -Destination "\\fileserver\loginscript\Archief\"
            LogWrite "Oud loginscript verplaatst naar archief"
        }
        catch{
            LogWrite "Probleem bij verplaatsen van oud loginscript naar archief"
        }

        try{
            Move-Item -Path $printscript -Destination "\\fileserver\loginscript\Archief\"
            LogWrite "Oud printscript verplaatst naar archief"
        }
        catch{
            LogWrite "Probleem bij verplaatsen van oud printscript naar archief"
        }
    }
}

#exchange connectie sluiten
Get-PSSession | Remove-PSSession
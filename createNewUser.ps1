#functie om speciale tekens uit naam te verwijderen
function Remove-StringLatinCharacters
{
    PARAM ([string]$String)
    [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
}

#Connectie leggen met Exchange Server
$UserCredential = $Host.ui.PromptForCredential("Gegevens nodig voor Exchange connectie", "Gelieve een Exchange admin op te geven.", "", "NetBiosUserName")
#$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://exchvs01.waak.local/PowerShell/ -Authentication Kerberos
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://exchvs02.waak.local/PowerShell/ -Authentication Kerberos -Credential $UserCredential

Import-PSSession $Session

#emailparameters
$From = "servicedesk.ICT@waak.be"
$SMTPServer = "exchange.waak.local"
$SMTPPort = "25"
$encoding = [System.Text.Encoding]::UTF8

#Ophalen inputfile voor aanmaken nieuwe gebruiker
Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "CSV (*.csv)| *.csv"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

$inputfile = Get-FileName "\\fileserver\IVA\scripts"
$UserList = Import-Csv $inputfile
$server = 'DOMCTRL01'

#overlopen gebruikers in inputfile en per lijn een gebruiker aanmaken
foreach ($user in $UserList)
{
    $firstName = Remove-StringLatinCharacters -String $user.voornaam
    $lastName = Remove-StringLatinCharacters -String $user.achternaam

    $completedFirstName = $false
    $completedLastName = $false
    $retrycount = 0

    #aanvullen voornaam als die minder dan 4 letters heeft
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

    #aanvullen achternaam als die minder dan 4 letters heeft
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

    $Username = $($firstName + $lastName).ToUpper()
    Write-Host $Username

    #als de gebruikersnaam reeds in gebruik is valt de laatste letter weg en wordt deze vervangen door een cijfer 0-9
    if (Get-ADUser -Filter "SamAccountName -eq '$Username'" -Server $server) {
        Write-Host "Gebruikersnaam $username is reeds in gebruik"

        $i = 1 
        while ($i -lt 9) { 
            $i +=1 
         
            if (Get-ADUser -Filter "SamAccountName -eq '$($Username.subString(0,7) +$i)'" -Server $server) { 
                Write-Host "Gebruikersnaam $($Username.subString(0,7) +$i) is reeds in gebruik." 
            } 
            else {break} 
        } 

        Write-Host "Gebruikersnaam $($Username.subString(0,7) +$i) is beschikbaar"
        $Username =  $($Username.subString(0,7) +$i)
    }
    else{
        Write-Host "$Username is beschikbaar." 
    }

    try{
        #effectief aanmaken van de gebruiker
        New-ADUser -SamAccountName $username -UserPrincipalName "$($username)@waak.be" -GivenName $user.voornaam -Surname $user.achternaam `
        -DisplayName ($user.achternaam + " " + $user.voornaam) -Name ($user.achternaam + " " + $user.voornaam) -AccountPassword (ConvertTo-SecureString -AsPlainText "azerty" -Force) `
        -Enabled $true -PasswordNeverExpires $false -Initials ($user.voornaam.Substring(0,1) + $user.achternaam.Substring(0,1)) `
        -Path "OU=Standaard_Gebruikers,OU=Gebruikers,OU=WAAK - Productie,DC=waak,DC=local" -Description $user.beschrijving `
        -Fax $user.Fax -Department $user.afdeling -Title $user.functie -Server $server

        #zorgen dat gebruiker zeker aangemaakt is
        Start-Sleep 10
        #mailbox van gebruiker activeren
        Enable-Mailbox $Username
        #Oracle full access geven op mailbox
        Get-Mailbox $Username | Add-MailboxPermission -User oracle -AccessRights FullAccess -InheritanceType All

        #Als de gebruiker gekopieerd wordt van een bestaande gebruiker krijgt hij ook hetzelfde loginscript en aangepast printscript
        if($user.bestaandeGebruiker -ne $null){
            try{
                $oldUser = Get-ADUser $user.bestaandeGebruiker -Properties * -Server $server
                $loginscript = Get-Childitem –Path "\\waak.local\SYSVOL\waak.local\scripts\$($oldUser.scriptPath)" -File -Recurse -ErrorAction SilentlyContinue
                $pos = $loginscript.Name.IndexOf("_")
                $leftPart = $loginscript.Name.Substring(0, $pos)
                $rightPart = $loginscript.Name.Substring($pos+1)
                $scriptPath = $($leftPart+ "_" + $username +".bat")

                $string = Select-String -Path "\\waak.local\SYSVOL\waak.local\scripts\$($Olduser.scriptPath)" -Pattern "addprinter"  | Select-Object Line
                $string = $string.Line

                $string = $string.ToString()
                $printscript = $string.Substring(8)

                (Get-Content $printscript).ToLower() | ForEach-Object {
                    $_.replace('printprdvs01', 'printprdvs03').replace("$($oldUser.samAccountName.ToLower())", "$($username)") }| Set-Content "\\fileserver\loginscript\printers\$($username)_addprinter.vbs"
                (Get-Content $loginscript.PSPath).ToLower().Replace("$($oldUser.SamAccountName.ToLower())","$username") | Set-Content "\\waak.local\SYSVOL\waak.local\scripts\$scriptPath"

                Set-ADUser -Identity $username -ScriptPath $scriptPath -Server $server
                Add-ADGroupMember 'G_Homes' $username -Confirm:$False -Server $server               
            }
            Catch{
                Write-Host "Probleem bij aanmaken van de gebruiker"
            }   
        }
        else{
            Set-ADUser -Identity $username -ScriptPath $user.loginscript -Server $server
            Add-ADGroupMember 'G_Homes' $username -Confirm:$False -Server $server
        }
    }
    catch{
    }
    #kopieren van groepen naar de nieuwe gebruiker
        if($user.bestaandeGebruiker -ne $null){
        Get-ADPrincipalGroupMembership -Identity $oldUser.samAccountName -Server $server | % {Add-ADPrincipalGroupMembership -Identity $Username -MemberOf $_ -Server $server}
        Write-Host "Groepen van gebruiker gekopieerd"
        }     

    try{
        #emails sturen naar Jan lewylle voor protime en Steven Vandenberghe voor CRM
        $to = "jan.lewylle@waak.be"
        $Subject = "Nieuwe gebruiker $($username) aangemaakt"
        $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag Jan</p>

<p>Er werd zonet een nieuwe gebruiker $($username) aangemaakt voor $($user.voornaam) $($user.achternaam).<br>
Is het mogelijk om hiervoor in Protime het nodige te doen?</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
        Send-MailMessage -From $From -to $to -Subject $Subject -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding

        if($user.crm -eq 'ja'){ 
            $to = "eric.bonne@waak.be"
            $Subject = "Nieuwe gebruiker $($username) aangemaakt"
            $mail = "
<span style='font:Calibri;font-size:12pt'>
<p>Dag Eric</p>

<p>Er werd zonet een nieuwe gebruiker $($username) aangemaakt voor $($user.voornaam) $($user.achternaam)<br>
Is het mogelijk om hiervoor in CRM het nodige te doen?</p> 

<p>Alvast bedankt!</p> 

<p>Helpdesk ICT</p>
</span>
"
            Send-MailMessage -From $From -to $to -Subject $Subject -Body $mail -SmtpServer $SMTPServer -BodyAsHtml -Encoding $encoding
        }
    }
    catch{
        Write-Host "Probleem bij het uitsturen van de emails"
    } 
}

Get-PSSession | Remove-PSSession
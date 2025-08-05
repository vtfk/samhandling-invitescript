# Oppdatering til ModernAuth (for eksisterende organisasjoner)
**Må gjøres før 31.12.2022**
- Stopp scriptet (tasken) om det kjører før du gjør endringer
- Åpne Powershell med brukeren som skal kjøre scriptet. ![image](https://user-images.githubusercontent.com/10476574/206709727-ac3229cb-cb28-4017-a213-7301d278d2de.png)
- Sjekk at du har Windows Credential Manager på serveren. Om den mangler, installer med kommandoen:

    `Install-Module -Name CredentialManager -AcceptLicense -AllowClobber -Force -Verbose -Scope AllUsers`
- Installer powershell PnP Module med kommandoen  ~~`Install-Module -Name "PnP.PowerShell`~~ 
> [!IMPORTANT]  
> På grunn av [issues med nyere versjoner av PNP](https://learn.microsoft.com/en-us/answers/questions/1196279/import-module-could-not-load-file-or-assembly-syst), må eldre versjon legges inn: `Install-Module -Name "PnP.PowerShell" -RequiredVersion 1.12.0 -Force -AllowClobber`
- Kjør først kommandoen under for å sette nytt passord på PNP-brukeren du har fått fra VTFK:
   
    `Connect-PnPOnline -Url https://samhandling.sharepoint.com/sites/b2bmembershipdata -clientid af65f65a-6b1b-4499-81e5-1540fba4431e -Interactive`  
- Logg på i påloggingsvinuet som dukker opp med PNP-brukeren du har fått av VTFK – sett nytt passord, og lagre dette trygt 
- Kjør kommandoen under for å legge inn credentials med det NYE PASSORDET til PNP-brukeren i Windows Credential Store: 

    `New-StoredCredential -Comment 'Samhandling-service-bruker' -Credentials $(Get-Credential) -Target '<organisasjon>-pnp-user@samhandling.onmicrosoft.com' -Persist ‘LocalMachine’` 
- Kjør kommandoen under for å bekrefte at passordet har blitt lagret og brukeren har tilgang på SharePoint:
    `Connect-PnPOnline -Url https://samhandling.sharepoint.com/sites/b2bmembershipdata -clientid af65f65a-6b1b-4499-81e5-1540fba4431e -Credential  (Get-StoredCredential -Target "<organisasjon>-pnp-user@samhandling.onmicrosoft.com") `
- Oppdater konfigurasjon i invite-skriptet (linje 27, 28 og 90 i originalskriptet. Se under:).
```ps1
#region Script Configuration: Source Azure AD Tenant

# Add source AAD tenant ID
$configSourceTenantID = "organisasjon.onmicrosoft.com"

# Add UserPrincipalName for AAD Service Account in source AAD tenant
$configSourceServiceAccountUPN = "Samhandlingb2binviteUser@organisasjon.no"


### DENNE MÅ LEGGES TIL ### 
# Add UserPrincipalName for PnP Service Account in samhandling AAD tenant (provided by samhandling.org host county (VTFK))
$configSourcePnPServiceAccountUPN = "<organisasjon>-pnp-user@samhandling.onmicrosoft.com"
### END DENNE MÅ LEGGES TIL ###


# Add SecureString for AAD Service Account password in source AAD tenant. See readme how to create this
$configSourceServiceAccountSecurePassword = 'longsupersecurestring'

# Add AAD Groups to scope B2B Users in source AAD tenant
$configSourceGroupsToInvite = "TILGANGSGRUPPE1", "TILGANGSGRUPPE2", "TILGANGSGRUPPE3"

# Add a filename and path for saving local logfile with invited users data
$configSourceLogfilePreviouslyInvitedUsers = "D:\localScriptPath\b2binvitedusers-organization.txt"

# Add a filepath for creating local csv file with membership data (exports to Master Organization)
$configSourceMembershipDataCsv = "D:\localScriptPath\export-membershipdata-organization.csv"

# Enable extensive logging to EventLog
$configSourceExtensiveLogging = $true

#endregion




#region Set Parameters

    # Set parameters
    $GLOBAL:Configuration = @{

        SourceTenantID = $configSourceTenantID
        SourceSvcUPN = $configSourceServiceAccountUPN
        
        ##### DENNE RADEN MÅ OGSÅ LEGGES TIL ###  #####
        SourcePnPSvcUPN = $configSourcePnPServiceAccountUPN 
        ##### END DENNE RADEN MÅ OGSÅ LEGGES TIL ###  #####
        
        SourceSvcPwd = $configSourceServiceAccountSecurePassword
        SourceAADInviteGroups = $configSourceGroupsToInvite
        TargetTenantID = $configTargetTenantID
        TargetSPOSiteUrl = $configTargetSPOSiteUrl
        TargetSPODocLibrary = $configTargetSPODocLibraryName
        LogfilePreviouslyInvitedUsers = $configSourceLogfilePreviouslyInvitedUsers
        CsvfileMembershipData  = $configSourceMembershipDataCsv
        ExtensiveLogging = $configSourceExtensiveLogging
        
    }

```
- **VIKTIG!** Bytt ut den eksisterende modulen *Azure-AD-B2B-Invite-Module.psm1* med den nye modulen som bruker PnP: [ny modul-fil](./Azure-AD-B2B-Invite-Module.psm1) (kall f. eks den andre module_old først, også legger du inn den nye som erstatter, slik at hovedskriptet bruker den nye modulen) 
- Nå kan du kjøre scriptet som før (starte tasken)

# Oppsett av Invite-script for nye organisasjoner
Beskriver hvordan partnerorganisasjoner kan melde "lokale" AzureAD-brukere inn og ut som gjestebrukere i Samhandling.org. Dette håndteres av PowerShellskript som må kjøres hos den enkelte partnerorganisasjon. Her følger beskrivelse på hvordan dette gjøres.

![image](https://user-images.githubusercontent.com/10476574/206708780-61b122bd-61b3-403d-8f8b-854a6704bfb5.png)


Administrasjon av tilgangen gjøres ved å melde brukere inn og ut av grupper i hver enkelt partnerorganisasjons AzureAD i Office365. Det kreves litt arbeid for å få på plass lokalt skript, og hvordan dette gjøres er beskrevet i dette dokumentet.
Skriptet er utviklet av Vestfold og Telemark fylkeskommune. Denne veiledningen er en forenklet utgave av den fullstendige dokumentasjonen

## Oppsett og førstegangs-konfigurasjon

### Forutsetninger
- Organisasjonen må ha O365 lisenser
- Brukerne må være i AzureAd
- Primary e-postadresse må være utfylt på brukerobjektene i AzureAD

### Parameterutveksling
Følgende trenger VFK fra partnerorganisasjon:
1.	UPN til servicekonto i Azure AD
2.	Navn på grupper og hva de skal ha tilgang til

Følgende får partnerorganisasjon fra VTFK:

3.	Påloggings URL som servicekonto i pkt 1 må logge seg på med.
Disse parameterne vil bli forklart nedenfor. 

### Servicekonto
Det må opprettes en Windows-konto som skal kjøre det lokale skriptet.

Det må også opprettes en servicekonto i AzureAD der brukere skal inviteres fra. Denne kontoen må ha lik suffix-adresse i UserPrincipalName (UPN) som brukerne som skal meldes inn. Det er ikke behov for spesielle privilegier. Eksempel på konto: *samhandlingb2binvite@vtfk.no*

Send kontoens UPN til VTFK på mailadresse *servicedesk@vestfoldfylke.no*, slik at VFK kan legge denne inn i Samhandling.org tenanten. VTFK sender en URL i retur som må besøkes. 

1.	Besøk URL'en og logg på med servicekontoens brukernavn og passord

    
2.	Kryptere passord for servicekontoen (skal benyttes i skript)
    1.	Start PowerShell ISE som Windows-servicekontoen som ble opprettet tidligere.
    2.	Kjør følgende kode:
 `Read-Host -AsSecureString | ConvertFrom-SecureString`

    3.	Skriv inn passordet til AzureAD servicekontoen
    4.	Resultatet er den krypterte strengen som skal benyttes i [Grupper](#grupper). Ta derfor vare på denne.

**MERK:**
Hvis Powershell-scriptet flyttes til en annen server, eller en annen Windows servicekonto skal ta over kjøringen av scriptet, så må man kjøre Powershell-kommandoen igjen for å opprette ny kryptert string. Merk at brukere med lokal-administratortilgang på serveren der strengen krypteres, kan i teorien hente ut passordet i klartekst.

### Grupper
Brukere blir meldt inn og gitt tilgang til samhandling.org basert på grupper i partnerorganisasjonen AzureAD. Opprett en eller flere grupper i AzureAD, meld brukerne inn i disse avhengig av hva de skal ha tilgang til og noter navnet på den/disse. Dette vil bli brukt videre i [skript](#skript).

Eksempel:

| **Gruppe i lokalt AAD** |
| --- |
| samhandling-ITforum |
| samhandling-HRforum |


### Skript
Skriptet består av to filer:

Azure-AD-B2B-Invite-Script.ps1 og Azure-AD-B2B-Invite-Module.psm1. Dette må kjøres på en server som har tilgang til Office365. I tillegg må serveren ha AzureAD Powershell-modulen og SharePoint Online Client Components SDK installert. Disse kan lastes ned herfra:

- AzureAD Powershell-modul (kjøres i PowerShell som administrator): `Install-Module -Name AzureAD`

- PnP PowerShell (kjøres i PowerShell som administrator): `Install-Module -Name "PnP.PowerShell"`
#### Plassering av skriptet
Legg skriptet (begge filene) i en mappe på serveren (for eksempel c:\Script\)
#### Logging
For at Powershell-scriptet skal kunne loggføre så må det opprettes en ny EventLog. Dette kan gjøres fra Powershell (elevert som lokal administrator på serveren) med følgende kommando:

`New-EventLog -LogName Application -Source "B2BInviteScript"`

Når scriptet kjører så vil det logge til den nye event loggen som dermed kan overvåkes. Både feil og varsler blir skrevet til loggen og vil dermed kunne ageres på om feil skulle oppstå. Se kapittelet om overvåking og feilsøking for mer informasjon.

Merk at hvis AzureAD, SharePoint PnP eller event loggen mangler på serveren der scriptet kjøres, så vil scriptet feile og stoppe.
#### Parametersetting
Åpne PS1-fila i en dertil egnet editor (for eks. VSCode) og rediger følgende parametere:

| Parameter | $configSourceTenantID |
| --- | --- |
| Beskrivelse | AzureAD tenant der brukere skal inviteres fra |
| Eksempel | "vtfk.onmicrosoft.com" |

| Parameter | $configSourcePnPServiceAccountUPN |
| --- | --- |
| Beskrivelse | PnP service-bruker som blir levert fra Samhandling.org-tenanten (fra VTFK) |
| Eksempel | vtfk-pnp-user@samhandling.onmicrosoft.com |

| Parameter | $configSourceServiceAccountUPN |
| --- | --- |
| Beskrivelse | UserPrincipalName for b2binvite-servicekonto. Se [forutsetning](#forutsetninger) |
| Eksempel | "samhandlingb2binvite@vtfk.no" |

| Parameter | $configSourceServiceAccountSecurePassword |
| --- | --- |
| Beskrivelse | Den krypterte strengen som ble laget i [servicekonto](#servicekonto) |
| Eksempel | "01000000d08c9ddf0000d08c9ddf0115d01000000d08c9ddf0115d101000000d08c9ddf0115d101000000d08c9ddf0115d101000000d08c9ddf0115d101000000d08c9ddf0115d1" |

| Parameter | $configSourceGroupsToInvite |
| --- | --- |
| Beskrivelse | AzureAD-grupper som det skal meldes inn brukere fra. Disse ble definert i [Grupper](#Grupper). Skriv inn gruppene kommaseparert med anførselstegn rundt hvert gruppenavn. 
|Eksempel | "AADGroup1","AADGroup2","AADGroup4" |

| Parameter | $configSourceLogfilePreviouslyInvitedUsers |
| --- | --- |
| Beskrivelse | For at Powershell-scriptet skal unngå å kjøre invitasjon på nytt for mailadresser/brukere som allerede er inviterte så lagrer scriptet en loggfil lokalt på serveren med alle inviterte mailadresser. Denne loggfilen vil importeres hver gang scriptet kjører og brukes til å filtrere ut allerede inviterte mailadresser før invitasjonsrutinen starter. **Det er viktig at Windows-servicekontoen som kjører scriptet har skrivetilgang til området/filen som defineres** |
| Eksempel | "c:\log\b2binvitedusers.txt" |

| Parameter | $configSourceMembershipDataCsv |
| --- | --- |
| Beskrivelse | Data om medlemskap blir lagt inn I en CSV fil lokalt som blir overført til samhandling.org-tenanten. Skriv inn filstien til lokalt område der denne filen blir mellomlagret. |
| Eksempel | "c:\log\export-membershipdata.csv" |

| Parameter | $configSourceExtensiveLogging |
| --- | --- |
| Beskrivelse | Powershell-scriptet vil alltid logge til «Application» eventlog på den lokale serveren slik at feilsøking og overvåking blir enklere. I normal drift kan dette parameteret være satt til $false, da blir det kun opprettet events ved start og stopp av scriptet (med resultater), samt advarsler og feilsituasjoner. Men hvis man ønsker å se mer detaljer ved kjøring av scriptet, kan man sette parameteret til $true, da vil scriptet logge all «verbose output» til eventlog |
| Eksempel | $false |

De resterende parameterne er allerede definert.
#### Kjøring av skript
Vi anbefaler at skriptet settes opp til å kjøre jevnlig ved hjelp av Scheduled Tasks med Windowskontoen definert i [Servicekonto](#servicekonto)


####################################################################################################################
##                                                                                                                  ##
##  -- Azure AD (AAD) B2B Auto-Invite Script --                                                                     ##
##                                                                                                                  ##
##  Automatically invite users from specific AAD groups in source AAD tenant to target AAD tenant as B2B-users      ##
##  The script can also report groups and members in source to the target for further processing (group invites ++) ##
##                                                                                                                  ##
##  Written by Stian A. Strysse, Lumagate AS - stian.strysse@lumagate.com                                           ##
##  15 Jan 2018 - First version                                                                                     ##
##  14 Mar 2018 - Added features (report groups and members in source to target tenant for further processing)      ##
##  09 Dec 2022 - Upgraded to support modern auth. Moved to GitHub Jørgen, Robin and Nils                           ##
##                                                                                                                  ##
##  Please read the configuration guide for details on how to set up service accounts, scheduled tasks and logging  ##
##  Note: Only edit values within the 'Script Configuration: Source/Target Azure AD Tenant' regions                 ##
##                                                                                                                  ##
####################################################################################################################

#region Script Configuration: Source Azure AD Tenant

# Add source AAD tenant ID
$configSourceTenantID = "organisasjon.onmicrosoft.com"

# Add UserPrincipalName for AAD Service Account in source AAD tenant
$configSourceServiceAccountUPN = "Samhandlingb2binviteUser@organisasjon.no"

# Add UserPrincipalName for PnP Service Account in samhandling AAD tenant (provided by samhandling.org host county)
$configSourcePnPServiceAccountUPN = "organisasjon-pnp-user@samhandling.onmicrosoft.com"

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

#region Script Configuration: Target Azure AD Tenant

# Add target AAD tenant ID
$configTargetTenantID = "samhandling.onmicrosoft.com"

# Add target SPO Site URL
$configTargetSPOSiteUrl = "https://samhandling.sharepoint.com/sites/b2bmembershipdata"

# Add target SPO Library
$configTargetSPODocLibraryName = "membershipcsvdata"

#endregion


###################################################################################################################
####  Warning: Do not edit below this line!  ########################################################################
###################################################################################################################


#region Import Required Modules

try {
  Import-Module $($PSScriptRoot + "\Azure-AD-B2B-Invite-Module.psm1") -Force -ErrorAction Stop
  Import-Module AzureAD -Force -ErrorAction Stop
}

catch {
  # Catch any Errors and report to EventLog before exiting script
  Write-EventLogB2B "Azure AD B2B Auto-Invite Script aborted due to an error: $($Error -join "`n`n")" -EventType Error
  exit
}

#endregion


#region Set Parameters

# Set parameters
$GLOBAL:Configuration = @{

  SourceTenantID                = $configSourceTenantID
  SourceSvcUPN                  = $configSourceServiceAccountUPN
  SourcePnPSvcUPN               = $configSourcePnPServiceAccountUPN
  SourceSvcPwd                  = $configSourceServiceAccountSecurePassword
  SourceAADInviteGroups         = $configSourceGroupsToInvite
  TargetTenantID                = $configTargetTenantID
  TargetSPOSiteUrl              = $configTargetSPOSiteUrl
  TargetSPODocLibrary           = $configTargetSPODocLibraryName
  LogfilePreviouslyInvitedUsers = $configSourceLogfilePreviouslyInvitedUsers
  CsvfileMembershipData         = $configSourceMembershipDataCsv
  ExtensiveLogging              = $configSourceExtensiveLogging
        
}

# Create ResultsLog
$ResultsLog = New-Object System.Collections.ArrayList

# Create array for scoped users
$ScopedUsers = New-Object System.Collections.ArrayList

# Create array for eligible users
$FilteredScopedUsers = New-Object System.Collections.ArrayList

#endregion


#region Connect to source Azure AD and get scoped users

try {

  # Start script
  Write-EventLogB2B "Azure AD B2B Auto-Invite Script started" -ErrorAction Stop

  # Connect to source Azure AD
  Write-EventLogB2B "Connecting to source Azure AD ($($GLOBAL:Configuration.SourceTenantID)) as $($GLOBAL:Configuration.SourceSvcUPN)" -VerboseOnly:$true
  $AzureADSourceCredential = New-Object System.Management.Automation.PSCredential($GLOBAL:Configuration.SourceSvcUPN, (ConvertTo-SecureString $GLOBAL:Configuration.SourceSvcPwd)) -ErrorAction Stop
  $AzureADSourceSession = Connect-AzureAD -Credential $AzureADSourceCredential -TenantId $GLOBAL:Configuration.SourceTenantID -ErrorAction Stop

  # Get members from scoped groups and add to scoped users array
  $GLOBAL:Configuration.SourceAADInviteGroups | ForEach-Object {
    Write-EventLogB2B "Searching for AAD Group: $($_)" -VerboseOnly:$true
    $AzureADGroup = Get-AzureADGroup -Filter "DisplayName eq '$($_)'" -ErrorAction Stop

    if ($AzureADGroup) {
      Write-EventLogB2B "Retrieving members in AAD Group: $($_)" -VerboseOnly:$true
      $AzureADGroupMembers = Get-AzureADGroupMember -All:$true -ObjectId $AzureADGroup.ObjectId
      Write-EventLogB2B "Found $($AzureADGroupMembers.count) members in AAD Group: $($_)" -VerboseOnly:$true

      $AzureADGroupMembers | Where-Object { $_.AccountEnabled } | Select-Object @{Name = "SourceTenant"; Expression = { $GLOBAL:Configuration.SourceTenantID } }, @{Name = "MemberOf"; Expression = { $AzureADGroup.DisplayName } }, DisplayName, Mail, UserPrincipalName, UserType | ForEach-Object {
        $ScopedUsers.Add($_) | Out-Null
      }

    }
    else {
      Write-EventLogB2B "Could not find Azure AD Group: $($_)" -EventType Warning
    }
  }
}

catch {
  # Catch any Errors and report to EventLog before exiting script
  Write-EventLogB2B "Azure AD B2B Auto-Invite Script aborted due to an error: $($Error -join "`n`n")" -EventType Error
  exit
}

finally {        
  # Disconnect from source Azure AD if connected
  if ($AzureADSourceSession) {
    Write-EventLogB2B "Disconnecting from source Azure AD ($($GLOBAL:Configuration.SourceTenantID))" -VerboseOnly:$true
    Disconnect-AzureAD
  }
}

#endregion


#region Report Group Memberships to Target tenant

try {

  # Verify that $ScopedUsers contains data
  if ($ScopedUsers.count -ne 0) {
    Write-EventLogB2B "$($ScopedUsers.count) scoped group memberships to report to Targent tenant" -VerboseOnly:$true

    # Export CSV file locally    
    Write-EventLogB2B "Exporting CSV to local file pending transfer at $($GLOBAL:Configuration.CsvfileMembershipData)" -VerboseOnly:$true     
    $ScopedUsers | Select-Object SourceTenant, MemberOf, Mail, UserPrincipalName | Export-Csv -Path $GLOBAL:Configuration.CsvfileMembershipData -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    # Transfer data to Master Organization
    Invoke-CsvFileUpload -ExportFile $GLOBAL:Configuration.CsvfileMembershipData -SourceTenantID $GLOBAL:Configuration.SourceTenantID -SPOSiteUrl $GLOBAL:Configuration.TargetSPOSiteUrl -SPODocLibraryName $GLOBAL:Configuration.TargetSPODocLibrary -ErrorAction Stop
            
    Write-EventLogB2B "Scoped group memberships reported successfully to Target tenant"

  }

  else {
    Write-EventLogB2B "No scoped group memberships to report to Target tenant"
  }
}

catch {
  # Catch any Errors and report to EventLog before exiting script
  Write-EventLogB2B "Azure AD B2B Auto-Invite Script aborted due to an error: $($Error -join "`n`n")" -EventType Error
  exit
}

#endregion


#region Verify Data

try {
  # Import logfile of previously invited users as hashtable
  $PreviouslyInvitedUsers = @{} ; Get-Content -Path $GLOBAL:Configuration.LogfilePreviouslyInvitedUsers -ErrorAction SilentlyContinue | ForEach-Object {
    $PreviouslyInvitedUsers[$_] = $true
  }

  # Verify if list with previously invited users exists, else write Event Warning
  if ($PreviouslyInvitedUsers.Count -eq 0) {
    Write-EventLogB2B "Could not locate a list with previously invited email addresses at $($GLOBAL:Configuration.LogfilePreviouslyInvitedUsers). All eligible users will be invited." -EventType Warning
  }

  # Filter scoped users: remove duplicates, users without email, already invited users, guests
  foreach ($User in $ScopedUsers) {

    # Verify if user has email address
    if (($User.Mail -ne $null) -and ($User.Mail -ne '')) {

      # Verify if user is not a Guest in source AAD tenant
      if ($User.UserType -ne 'Guest') {
                    
        # Verify if user is not present in several scoped groups
        if ($FilteredScopedUsers.UserPrincipalName -notcontains $User.UserPrincipalName) {

          # Add user to eligible list if not already invited
          if (!$PreviouslyInvitedUsers.ContainsKey($User.Mail)) {
            Write-EventLogB2B "Added to eligible list: $($User.UserPrincipalName)" -VerboseOnly:$true
            $FilteredScopedUsers.Add($User) | Out-Null
          }

          else {
            Write-EventLogB2B "Skipped - user is previously invited according to logfile: $($User.UserPrincipalName)" -VerboseOnly:$true
          }
        }
      }

      else {
        Write-EventLogB2B "Skipped - user is a Guest in source AAD tenant: $($User.UserPrincipalName)" -VerboseOnly:$true
      }
    }

    else {
      Write-EventLogB2B "Skipped - user does not have an email address in source AAD tenant: $($User.UserPrincipalName)" -VerboseOnly:$true
    }      
  }

  # Check if eligible users list is empty after filtering, if so exit script
  if ($FilteredScopedUsers.Count -eq 0) {
    Write-EventLogB2B "Azure AD B2B Auto-Invite Script ended - no new users to process"
    exit
  }

  Write-EventLogB2B "Found a total of $($FilteredScopedUsers.count) unique, eligible users in source AAD ($($ScopedUsers.count) before filtering and removing duplicates)" -VerboseOnly:$true

}

catch {
  # Catch any Errors and report to EventLog before exiting script
  Write-EventLogB2B "Azure AD B2B Auto-Invite Script aborted due to an error: $($Error -join "`n`n")" -EventType Error
  exit
}

#endregion


#region Connect to target Azure AD and B2B-invite eligible users from $ScopedUsers

try {
  # Connect to target Azure AD
  Write-EventLogB2B "Connecting to target Azure AD ($($GLOBAL:Configuration.TargetTenantID)) as $($GLOBAL:Configuration.SourceSvcUPN)" -VerboseOnly:$true
  $AzureADTargetCredential = New-Object System.Management.Automation.PSCredential($GLOBAL:Configuration.SourceSvcUPN, (ConvertTo-SecureString $GLOBAL:Configuration.SourceSvcPwd)) -ErrorAction Stop
  $AzureADTargetSession = Connect-AzureAD -Credential $AzureADTargetCredential -TenantId $GLOBAL:Configuration.TargetTenantID -ErrorAction Stop | Out-Null

  Foreach ($User in $FilteredScopedUsers) {     

    # Do guest invitation
    $InvitationResult = New-AzureADMSInvitation -InvitedUserDisplayName $User.DisplayName -InvitedUserEmailAddress $User.Mail -SendInvitationMessage:$false -InviteRedirectUrl "https://myapps.microsoft.com" -ErrorAction Continue
    $ResultsLog.Add($InvitationResult) | Out-Null

    # Verify guest invitation
    if (($InvitationResult.Status -eq 'Accepted') -or ($InvitationResult.Status -eq 'PendingAcceptance')) {
      Write-EventLogB2B "Invite of $($User.Mail) was successfull" -VerboseOnly:$true
      $User.Mail | Out-File -FilePath $GLOBAL:Configuration.LogfilePreviouslyInvitedUsers -Append -Encoding utf8 -ErrorAction Stop
    }

    # Write Error if guest invitation was not successfull
    else {
      Write-EventLogB2B "Error during invite of $($User.Mail): $($Error -join "`n`n")" -EventType Error
      $ErrorCounter++

      if ($ErrorCounter.count -ge 5) {
        Write-EventLogB2B "Azure AD B2B Auto-Invite Script aborted due to 5 failed invitations, see event log for more details" -EventType Error
      }
    }
  }

  Write-EventLogB2B "Azure AD B2B Auto-Invite Script ended: $((($ResultsLog.Status -eq 'Accepted').count + ($ResultsLog.Status -eq 'PendingAcceptance').count)) new invitations completed successfully"

}

catch {
  # Catch any Errors and report to EventLog before exiting script
  Write-EventLogB2B "Azure AD B2B Auto-Invite Script aborted due to an error: $($Error -join "`n`n")" -EventType Error
  exit
}

finally {
  # Disconnect from source Azure AD if still connected
  if ($AzureADTargetSession) {
    Write-EventLogB2B "Disconnecting from source Azure AD ($($GLOBAL:Configuration.SourceTenantID))" -VerboseOnly:$true
    Disconnect-AzureAD
  }
}
    
#endregion
  

###################################################################################################################
####  End of Script  ################################################################################################
###################################################################################################################
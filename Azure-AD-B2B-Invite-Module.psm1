<#
.Synopsis
   Function for uploading a file to SharePoint Online using SharePoint PnP
.DESCRIPTION
   Function for uploading a file to SharePoint Online using SharePoint Pnp
.EXAMPLE
   Invoke-CsvFileUpload $file
#>

function Invoke-CsvFileUpload {
  [CmdletBinding()]
  [OutputType([string])]
  Param
  (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $false,
      Position = 0)]
    [String] $ExportFile,

    [Parameter(Mandatory = $true,
      ValueFromPipeline = $false,
      Position = 1)]
    [String] $SourceTenantID,

    [Parameter(Mandatory = $true,
      ValueFromPipeline = $false,
      Position = 2)]
    [String] $SPOSiteUrl,

    [Parameter(Mandatory = $true,
      ValueFromPipeline = $false,
      Position = 3)]
    [String] $SPODocLibraryName
  )

  Process {
    try {

      # Verify that local CSV file with membership data exists
      Write-EventLogB2B "Verifying that local Csv file with membership data exists at $ExportFile" -VerboseOnly:$true
      if (-Not (Test-Path -Path $ExportFile)) {
        Write-EventLogB2B "Local Csv file with membership data does not exist at $($ExportFile), cannot proceed" -EventType Warning
        throw "Local CSV file with membership data does not exist, script cannot proceed"
      }

      # PNP version
      # Connect to PNP Online
      Write-EventLogB2B "Connecting to SharePoint Online: $SPOSiteUrl - Library: $SPODocLibraryName" -VerboseOnly:$true
      Connect-PnPOnline -Url $SPOSiteUrl -ClientId "af65f65a-6b1b-4499-81e5-1540fba4431e" -Credential (Get-StoredCredential -Target $GLOBAL:Configuration.SourcePnPSvcUPN)
      # Upload CSV file to SPO Library
      Write-EventLogB2B "Trying to upload CSV file to SharePoint Online" -VerboseOnly:$true
      Add-PnPFile -Path $ExportFile -Folder $SPODocLibraryName -NewFileName (($SourceTenantID).Replace(".", "-") + ".csv")
            
      # Remove SPO Context
      Write-EventLogB2B "Disconnecting from SharePoint Online" -VerboseOnly:$true
      Disconnect-PnPOnline
      #>

    }

    catch {

      # Catch any Errors and report to EventLog before exiting script
      Write-EventLogB2B "Error:$_ Azure AD B2B Auto-Invite Script aborted due to an error during upload of CSV data to Master Organization. $($Error -join "`n`n")" -EventType Error
      exit

    }
  }
}

function Write-EventLogB2B {
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true,
      Position = 0)]
    $EventText, 

    [Parameter(Mandatory = $false,
      ValueFromPipeline = $false,
      Position = 1)]
    [ValidateSet("Information", "Error", "Warning")]
    [String] $EventType = "Information",

    [Parameter(Mandatory = $false,
      ValueFromPipeline = $false,
      Position = 2)]
    [String] $EventSource = "B2BInviteScript",

    [Parameter(Mandatory = $false,
      ValueFromPipeline = $false,
      Position = 3)]
    [Int] $EventId = 5500,

    [Parameter(Mandatory = $false,
      ValueFromPipeline = $false,
      Position = 4)]
    [Boolean] $VerboseOnly = $false
  )

  Process {
    # Send output to EventLog if applicable
    if (-Not($VerboseOnly) -or ($GLOBAL:Configuration.ExtensiveLogging)) {
      Write-EventLog -LogName Application -Source $EventSource -EntryType $EventType -EventId $EventId -Message $EventText
    }

    # Send output to Write-Verbose
    switch ($EventType) {
      { $EventType -eq "Information" } { Write-Verbose -Verbose -Message $EventText }
      { $EventType -eq "Error" } { Write-Error -Verbose -Message $EventText }
      { $EventType -eq "Warning" } { Write-Warning -Message $EventText }
    }
  }
}

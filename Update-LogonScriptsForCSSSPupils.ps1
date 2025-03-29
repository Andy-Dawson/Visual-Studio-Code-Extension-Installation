##########
#
# Script to check and set appropriate logon script for senior school CS users
#
# Requirements: This script uses a certificate and Enterprise App to connect to the Azure/Office 365tenant.
#               Ensure that the correct certificate is installed in the user store for the account running the script.
#               Ensure that the account running this script has permissions to modify required user accounts in AD.
#               PowerShell 7 with the Microsoft.Graph PowerShell module installed.
#
##########

# The variables below control whether messages will be displayed or logged, and the location of the log file
$global:LogOutput = $True
$global:WriteStdOutput = $True
$global:LogFileLoc = "C:\Support\Update-LogonScriptsforCSSSPupils.txt"

# Function to notify the user what's going on
function NotifyUser {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Message
	)

    # If we're writing std output...
    if ($global:WriteStdOutput) {
        Write-Host $Message
    }

    # If we're writing log file output...
    if ($global:LogOutput) {
        # Find current date and time to prepend the message
        $date = (Get-Date -Format "dd/MM/yyyy HH:mm:ss").ToString()
        $Message = "[" + $date + "]: " + $Message 
        $Message | Out-File -FilePath $global:LogFileLoc -Append
    }
}

# Function to return users from an AAD Group (and any sub-Groups of that Group)
function Get-membersFromAADGroup {
    [CmdletBinding()]
	param(
	    [Parameter(Mandatory)]
    	[string]$GroupId
	)

    # Let the user know that we've called the function (for debugging at this point)
    #NotifyUser "Function Get-MembersFromAADGroup called..."

    # Get the group information from the Id provided
    $GroupName = (Get-MgGroup -GroupId $GroupId).DisplayName
    NotifyUser "  o Getting users from Group $($GroupName) - $($GroupId)"

    # Empty array to contain the users we're going to return
    # Should be returned as a list of Ids, so will need to use $user.Id
    $ReturnUsers = @()

    # Now go ahead and get the group members (users)
    NotifyUser "  o Getting Group members (users)..."
    $gmusers = Get-MgGroupMemberAsUser -GroupId $GroupId -All
    NotifyUser "   o $($gmusers.count) Group members (users) returned"
    foreach ($gmuser in $gmusers) {
        # We want the username of each user returned, so get rid of the domain part
        $UserName = $gmuser.UserPrincipalName.ToLower().Replace("@<Domain>","")
        # Add the username to the list of users to return
        $ReturnUsers += $UserName
    }

    # Get the group owners (users)
    NotifyUser "  o Getting Group owners (users)..."
    $gousers = Get-MgGroupOwnerAsUser -GroupId $GroupId -All
    NotifyUser "   o $($gousers.count) Group owners (users) returned"
    # Remove the owners from the array of users we've returned - They will be the teaching staff and should not have the logon script set
    foreach ($gouser in $gousers) {
        # We want the username of each user returned, so get rid of the domain part
        $UserName = $gouser.UserPrincipalName.ToLower().Replace("@<Domain>","")
        # Remove owner(s) from the list of returned users
        $ReturnUsers = $ReturnUsers | Where-Object {$_ -ne $UserName}
    }

    # Return the list of users gathered
    return $ReturnUsers

} # End of function


# Main script starts here
# Create an empty array to store the IDs of the AAD Groupts we'll want to process
$AADGroups = @()
# Empty array to contain the list of staff and pupils for later comparison
$Users = @()

# Check whether there's a log file as specified at the top of the file. If it is > 250kB, then remove it and start again.
If (Test-Path -Path $global:LogFileLoc -PathType Leaf) {
    # The log file exists - check how large it is
    $LogFile = Get-ChildItem -Path $global:LogFileLoc
    if ($LogFile.Length -gt 250000) {
        # If the file is > 250kB, remove it
        Remove-Item -Path $global:LogFileLoc -Force
    }
}

# Check that we're running in a PS 7 window
if ($PSVersionTable.PSversion.Major -lt 7) {
    # We're running in a PS window that is not at least version 7
    throw "This script MUST be run in a PowerShell 7 window."
}

# Ensure that the Graph PowerShell module is installed
$GraphModule = Get-InstalledModule -Name Microsoft.Graph.Groups -ErrorAction SilentlyContinue
If (!($GraphModule)) {
    # The Microsoft.Graph.Groups module (a good indicator that Microsoft.Graph is installed) is not installed
    throw "This script REQUIRES that the Microsoft.Graph modules are installed."
}

# Make a connection to the Microsoft Graph - see https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0#app-only-access  for details on how to get this configured
NotifyUser "Connecting to the Microsoft Graph..."
Connect-MgGraph -ClientId <ClientId> -TenantId <TenantId> -CertificateThumbprint <CertThumbprint> -NoWelcome

# List of Teams requested by CS in '24-'25 academic year:
# 13A/CP1a-AAA-2024
# 13D/CP1b-BBB-2024
# 12B/CP1a-AAA-2024
# 12C/CP1b-BBB-2024
# 11A/CP1-AAA-2024
# 11B/CP1-BBB-2024
# 11C/CP1-BBB-2024
# 10A/Cp1-AAA-2024
# 10C/Cp1-BBB-2024
# 10B/Cp1-CCC-2024

# Get all of the AAD Groups that match our required list - may need to change this in future years
NotifyUser "Looking for Entra Groups to process..."
$Groups = Get-MgGroup -All | Where-Object {$_.DisplayName -like "1??/Cp1*"} # Need to use $AADGroups.Id later in this script

# Now check each group to see if the associated Team is archived and if so disregard.
foreach ($Group in $Groups) {
    # Note: Some Groups no longer have Teams associated with them - these need to also be filtered out
    $Team = Get-MgTeam -TeamId $Group.Id -ErrorAction SilentlyContinue
    if (($Team) -And ($Team.IsArchived -ne $True)) {
        # Add the Group ID to the list of IDs to process in a moment
        NotifyUser "  o Adding Group $($Group.DisplayName) to the list to process..."
        $AADGroups += $Group.Id
    } else {
        NotifyUser "  - Group $($Group.DisplayName) is either archived or has no associated Team, ignoring..."
    }
}

# Now assemble the list of users that we'll need - Note that we need ONLY the group members, NOT the group owners
NotifyUser "Processing user list..."
foreach ($AADGroup in $AADGroups) {
    NotifyUser "Processing group $($AADGroup)"
    # Call the function to get the list of users from a Group
    # Note that the output may contain duplicates, so we need to be careful when adding these to the final list of users to be used
    $ReturnedUsers = Get-MembersFromAADGroup -GroupId $AADGroup

    # Now process the list of returned users and add those that are not already in the master list to it
    if ($ReturnedUsers.count -gt 0) {
        foreach ($ReturnedUser in $ReturnedUsers) {
            # Check whether the returned user is already in the master list of users
            if (!($Users -contains $ReturnedUser)) {
                # Add the current member to the @Users array
                NotifyUser "  + Adding user $($ReturnedUser) to the master user list"
                $Users += $ReturnedUser
            } else {
                # The user is already in the list and should be skipped
                NotifyUser "  - User $($ReturnedUser) as already in the the master user list and will be skipped"
            }
        }
    }
}

# Let the user know how many users we have collected
NotifyUser "  ** $($Users.count) users returned from the Groups specified **"

# Now that we have a list of users, we need to process them
#  go through the list and ensure that all list members have the correct logon script set
#  then go through the list of users with this login script set and check that all of them are on the master users list; reset any that are not

NotifyUser "Checking generated user list for required logon script..."
foreach ($User in $Users) {
    NotifyUser "  o Processing user $($User)..."
    # Check each user account for the correct logon script
    $LogonScript = (Get-ADUser -Identity $User -Properties "ScriptPath").ScriptPath
    if ($LogonScript -ne "Senior-Pupils-PythonExtension.bat") {
        # Set the logon script to be the one we need to install/update the Python extension in VS Code
        NotifyUser "    o Setting logon script for $($User) to Senior-Pupils-PythonExtension.bat"
        Set-ADUser -Identity $User -ScriptPath "Senior-Pupils-PythonExtension.bat"
    } else {
        NotifyUser "    o Logon script for $($User) already set correctly"
    }
}

NotifyUser "Checking AD accounts using Senior-Pupils-PythonExtension.bat against the user list..."
$CSLogonScriptADUsers = (Get-ADUser -Filter "ScriptPath -eq 'Senior-Pupils-PythonExtension.bat'").samAccountName
# This will include all accounts that have their logon script set to this
foreach ($CSLogonScriptADUser in $CSLogonScriptADUsers) {
    if (!($Users -contains $CSLogonScriptADUser)) {
        # We have a user in the Group who is not in our list of users, remove them from the Group
        NotifyUser "  - User $($CSLogonScriptADUser) has logon script set to Senior-Pupils-PythonExtension.bat, but should not"
        NotifyUser "    - Setting user $($CSLogonScriptADUser) logon script to Senior-Pupils.bat"
        Set-ADUser -Identity $CSLogonScriptADUser -ScriptPath "Senior-Pupils.bat"
    }
}

# Finally disconnect from the Graph as we don't want to leave open connection lurking
NotifyUser "Disconnecting from the Microsoft Graph"
Disconnect-MgGraph

NotifyUser "Script complete"

# Visual-Studio-Code-Extension-Installation
Automatic installation of Visual Studio Code extension(s) for specific domain users.

## Introduction
This repository contains required components to install or upgrade pre-determined Visual Studio Code extensions for specific users.

At the school at which I work, we had a request to ensure that the Microsoft Python extension[^1] for Visual Studio Code be automatically installed for pupils taking Computer Science in specific years. Ideally we should be able to do this upon installation or upgrade of Visual Studio Code on the school computers, however there doesn't seem to be any way of centrally installing and updating extensions (please correct me if I'm wrong!). We tried a couple of approaches, but none of them worked as well as we wanted:

- Scripting the installation of the extension, the moving it to the central extension location - while this worked, the extension does not appear as installed by Visual Studio Code and is not automatically updated.
- Including the Python extension as a recommended extension in anything that the pupils open - The pupils did not always start from a folder containing Python files, and some pupils just closed the recommendation without installing the extension.

We therefore needed a way of doing the following:

- Ensure that the required extension(s) was installed or updated for a set of pupils, list to be provided by the computer science teaching staff.
- Keep the list of pupils for whom the extension was to be installed up-to-date with as little effort as possible.
- Ensure that any pupils for whom the extension should not be installed did not have this happen.

We also had one or two other complications that arose during the planning of this that needed to be factored into the solution:

- The list of pupils who needed the extension automatically installing was provided by membership of a set of Microsoft Teams/Office 365 Groups. While there may be other methods to determine the pupil list, I had just written some PowerShell for Teams/Groups membership lists that could work with little modification.
- The extension had to be either installed per-user or updated, if the extension was already installed in the user's profile on the computer they were using.
- We may need to add further extensions at a later date, so the solution needed to be extensible.
- The solution needed to be able to download extensions with the safeguarding web filtering and monitoring solutions that we use in place[^2].
- Not all school computers had Visual Studio Code installed, so any solution needed to take this into account and not attempt to install extensions if Visual Studio Code was not present on the machine.
- The teaching staff should not have the logon script set - they would already have the Python extension installed.

[^1]: The extension actually comprises 3 extension. Installing 'Python' automatically also installs pylance and the Python Debugger.

[^2]: Extension installation using the GUI worked happily, however scripting the installation required that additional steps be taken; more information below.

## Solution
As we utilise Active Directory for authentication, we can use a logon script to perform the required work to either install or upgrade one or more Visual Studio Code extensions.

Scripting the installation of Visual Studio Code extensions threw a network related error as the root certificate used by the network filtering solution is not automatically trusted (however this works happily using the GUI). We can however deal with this by:

1. Export the root certificate from the filtering solution as a pem format file.
2. Place this file somewhere all user accounts can see.
3. Use something like the following in the logon script to temporarily allow the use of the certificate: set NODE_EXTRA_CA_CERTS=\\CentralNetworkLocation\CiscoUmbrellaRootCA.pem

The solution therefore consists of three files:

1. The root certificate in pem format as mentioned above.
2. The logon script to be used by the pupils when they logon to a computer (Senior-Pupils-PythonExtension.bat). Note: This script assumes that Visual Studio Code is installed in the default location for x64 computers. If you install yours to a different location, you will need toi change the logic in the logon script.
3. A PowerShell script to keep track of which pupils should have this logon script applied and assign this to them and reset the script for those who do not need it (Update-LogonScriptsForCSSSPupils.ps1).

### Logon Script

The [logon script](https://github.com/Andy-Dawson/Visual-Studio-Code-Extension-Installation/blob/main/Senior-Pupils-PythonExtension.bat)
- Uses set NODE_EXTRA_CA_CERTS=\\<DomainFQDN>\NETLOGON\Certs\CiscoUmbrellaRootCA.pem to allow the download of extensions.
- Looks for "C:\Program Files\Microsoft VS Code\bin\Code.cmd" as a method for determining whether Visual Studio Code is installed.
- If Visual Studio Code appears to be present, looks for the presence of "ms-python.python" in the user's .vscode\extensions\extensions.json file.
- If present, triggers the update of this extension
- If not present, triggers the installation of this extension.

We could actually use the same command for both installation/update, however I prefer not to use '--force' if we don't have to.

### The PowerShell Script

The [PowerShell Script](https://github.com/Andy-Dawson/Visual-Studio-Code-Extension-Installation/blob/main/Update-LogonScriptsForCSSSPupils.ps1)
- Has some global variables at the top that control whether you want to log output and/or write to std output and where to log items to.
- Contains functions to notify the user (via the log or std output) and get members from an Extra Group.
- Tests for a few conditions (PowerShell 7 and the presence of the Microsoft.Graph.Groups module to indicate that the Microsoft.Graph modules are all installed).
- Connects to the Microsoft Graph using the method at https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0#app-only-access (note, you'll need to set this up first; it allows scripts to run against the Graph without requiring manual intervention)
- Looks for the requested Teams ignoring the archived Teams (we archive Teams at the end of the academic year in preparation for the new year's Teams creation).
- Creates a master list of users from the Teams located.
- Goes through the generated list of users and ensures that the correct logon script is set.
- Locates all domain users with 'Senior-Pupils-PythonExtension.bat' as their logon script and checks against the list of users generated, above, and resets/removes the logon script for those not on the list of users generated from the Teams.

### Putting it all Together

The complete solution is therefore:
- A PowerShell that is configured to run weekly on a server using a scheduled task to keep the list of users with the required logon script correctly configured. Note: The account that this script is configured to run as by the scheduled task needs appropriate rights in Active Directory to modify the users accounts that need updating.
- For the users configured with the appropriate logon script, each time they log onto a school computer that has Visual Studio Code installed, the Python extension is either automatically installed or updated.

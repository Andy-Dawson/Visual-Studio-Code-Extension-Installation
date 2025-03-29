REM This script installs or updates the Python extension for VS Code if Code is installed on the local computer

set NODE_EXTRA_CA_CERTS=\\<DomainFQDN>\NETLOGON\Certs\CiscoUmbrellaRootCA.pem

if exist "C:\Program Files\Microsoft VS Code\bin\Code.cmd" (
    REM Code appears to be installed - now look to see if the extension is registered
    >nul findstr /c:"ms-python.python" "C:\Users\%USERNAME%\.vscode\extensions\extensions.json" && (
        REM the extension was found in the file that denotes registered extensions - update it
        "C:\Program Files\Microsoft VS Code\bin\Code.cmd" --install-extension ms-python.python --force
    ) || (
        REM The extension was not registered, install it
        "C:\Program Files\Microsoft VS Code\bin\Code.cmd" --install-extension ms-python.python
    )
) else (
    REM Code is NOT present on the system, do nothing
)

:End

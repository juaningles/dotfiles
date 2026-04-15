@echo off
setlocal enabledelayedexpansion

rem Initialize environment variable
set "INSTALL_FLAG="
set "SEARCH_PATTERN="
set "AKS_PATTERN="
set "SUBSCRIPTION_IDS="

:process_args
if "%~1"=="" goto :after_args
if "%~1"=="--install" (
    set "INSTALL_FLAG=true"
    shift
    goto :process_args
)
if "%~1"=="--help" (
    call :print_usage
    exit /b
)
if "%~1"=="--query" (
    if "%~2"=="" (
        echo ERROR: query parameter is required for --query
        call :print_usage
        exit /b 2
    )
    set "SEARCH_PATTERN=%~2"
    echo Searching for subscription matching pattern: !SEARCH_PATTERN!
    
    rem Get subscription IDs from Azure CLI directly
    powershell -Command "$pattern = '%~2'; $subs = az account list | ConvertFrom-Json; $subs | Where-Object { $_.name -match $pattern } | ForEach-Object { $_.id }" > subs.txt
    echo Matching subscriptions found:
    type subs.txt
    for /f "tokens=*" %%i in (subs.txt) do set "SUBSCRIPTION_IDS=!SUBSCRIPTION_IDS! %%i"
    del subs.txt
    
    shift
    shift
    goto :process_args
)
if "%~1"=="--name" (
    if "%~2"=="" (
        echo ERROR: name parameter is required for --name
        call :print_usage
        exit /b 2
    )
    set "AKS_PATTERN=%~2"
    shift
    shift
    goto :process_args
)
if "%~1:~0,1%"=="-" (
    echo Unknown Option: %1
    call :print_usage
    exit /b 1
)

set "SUBSCRIPTION_IDS=!SUBSCRIPTION_IDS! %~1"
shift
goto :process_args

:print_usage
echo Usage:
echo     k8stool.cmd [options] [sub [sub ...]]
echo Options:
echo     --install                install credentials
echo     --query query_pattern    query for subscription names that match query_pattern
echo     --name name_pattern      filters for only names that match name_pattern
echo     --help                   display this help message
exit /b

:after_args
rem Check if the file exists and is empty
if exist subs.txt (
    for %%F in (subs.txt) do if %%~zF==0 del subs.txt
)

if not defined SUBSCRIPTION_IDS (
    if defined SEARCH_PATTERN (
        echo [91mNo subscriptions found matching pattern: !SEARCH_PATTERN![0m
    ) else (
        echo No subscriptions specified.
    )
    call :print_usage
    exit /b 1
)

rem Define color codes
set "GREEN=[92m"
set "RED=[91m"
set "RESET=[0m"
set "BLUE=[94m"

echo Working with subscriptions: !SUBSCRIPTION_IDS!
echo Looking for clusters matching: !AKS_PATTERN!

rem Process each subscription
set "found_clusters=false"

for %%s in (!SUBSCRIPTION_IDS!) do (
    echo.
    echo Processing subscription: %%s
    
    rem List AKS clusters and filter by name
    powershell -Command "try { $clusters = az aks list --subscription %%s | ConvertFrom-Json; if ($clusters) { $clusters | Where-Object { $_.name -match '!AKS_PATTERN!' } | ForEach-Object { Write-Host $_.name '|' $_.fqdn '|' $_.privateFqdn '|' $_.resourceGroup '|' %%s; $LASTEXITCODE = 0 } } } catch { Write-Host 'Error accessing subscription'; $LASTEXITCODE = 1 }" > clusters.txt
    
    if !ERRORLEVEL! neq 0 (
        echo !RED!FAIL!RESET! Error accessing subscription %%s
        echo.
        continue
    )
    
    for /f "tokens=1-5 delims=|" %%a in (clusters.txt) do (
        set "found_clusters=true"
        set "name=%%a"
        set "name=!name: =!"
        set "fqdn=%%b"
        set "fqdn=!fqdn: =!"
        set "pfqdn=%%c"
        set "pfqdn=!pfqdn: =!"
        set "rsrc=%%d"
        set "rsrc=!rsrc: =!"
        set "sub=%%e"
        set "sub=!sub: =!"
        
        echo !BLUE!#========================================================================!RESET!
        echo !BLUE!# !name!!RESET!
        echo !BLUE!#========================================================================!RESET!
        
        if defined INSTALL_FLAG (
            powershell -Command "Write-Host 'Running: nslookup !fqdn!'; $result = nslookup !fqdn!; $exitCode = $LASTEXITCODE; if ($exitCode -eq 0) { Write-Host '[92mPASS[0m nslookup !fqdn!'; $result } else { Write-Host '[91mFAIL[0m nslookup !fqdn!'; $result }"

            if not "!pfqdn!"=="" if not "!pfqdn!"=="null" (
                powershell -Command "Write-Host 'Running: nslookup !pfqdn!'; $result = nslookup !pfqdn!; $exitCode = $LASTEXITCODE; if ($exitCode -eq 0) { Write-Host '[92mPASS[0m nslookup !pfqdn!'; $result } else { Write-Host '[91mFAIL[0m nslookup !pfqdn!'; $result }"
            ) else (
                echo !BLUE!SKIPPED!RESET!	private fqdn not set
            )
            
            powershell -Command "Write-Host 'Running: az account set --subscription !sub!'; $result = az account set --subscription '!sub!' | Out-String; $exitCode = $LASTEXITCODE; if ($exitCode -eq 0) { Write-Host '[92mPASS[0m az account set --subscription !sub!'; $result } else { Write-Host '[91mFAIL[0m az account set --subscription !sub!'; $result }"
            
            powershell -Command "Write-Host 'Running: az aks get-credentials --resource-group !rsrc! --name !name! --overwrite-existing'; $result = az aks get-credentials --resource-group '!rsrc!' --name '!name!' --overwrite-existing | Out-String; $exitCode = $LASTEXITCODE; if ($exitCode -eq 0) { Write-Host '[92mPASS[0m az aks get-credentials'; $result } else { Write-Host '[91mFAIL[0m az aks get-credentials'; $result }"
            
            powershell -Command "Write-Host 'Running: kubelogin convert-kubeconfig -l azurecli'; $result = kubelogin convert-kubeconfig -l azurecli | Out-String; $exitCode = $LASTEXITCODE; if ($exitCode -eq 0) { Write-Host '[92mPASS[0m kubelogin convert-kubeconfig'; $result } else { Write-Host '[91mFAIL[0m kubelogin convert-kubeconfig'; $result }"
            
            powershell -Command "Write-Host 'Running: kubectl get nodes'; $result = kubectl get nodes | Out-String; $exitCode = $LASTEXITCODE; if ($exitCode -eq 0) { Write-Host '[92mPASS[0m kubectl get nodes'; $result } else { Write-Host '[91mFAIL[0m kubectl get nodes'; $result }"
        ) else (
            echo nslookup !fqdn!
            
            if not "!pfqdn!"=="" if not "!pfqdn!"=="null" (
                echo nslookup !pfqdn!
            ) else (
                echo !BLUE!SKIPPED!RESET!	private fqdn not set
            )
            
            echo az account set --subscription !sub!
            echo az aks get-credentials --resource-group !rsrc! --name !name! --overwrite-existing
            echo kubelogin convert-kubeconfig -l azurecli
            echo kubectl get nodes
        )
        
        echo.
    )
)

if exist clusters.txt del clusters.txt

if not "!found_clusters!"=="true" (
    echo.
    echo !RED!No clusters found matching "!AKS_PATTERN!" in the specified subscriptions.!RESET!
)

endlocal
exit /b
@echo off
setlocal enabledelayedexpansion

set "run_for_subs=%*"

rem Initialize environment variable
set "INSTALL_FLAG="

rem Initialize an empty string to store other arguments
set "OTHER_ARGS="
set "SEARCH_PATTERN="
set "AKS_PATTERN="

goto :process_args

:print_usage
for %%F in ("%0") do set "command_name=%%~nxF"
echo Usage:
echo     !command_name! [options] [sub [sub ...]]
echo Options:
echo     --install                install credentials
echo     --query query_pattern    query for subscription names that match query_pattern
echo     --name name_pattern      filters for only names that match name_pattern
exit /b

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
    
    rem Use PowerShell to query subscriptions instead of jq
    for /f "tokens=*" %%a in ('powershell -Command "(az account list | ConvertFrom-Json | Where-Object { $_.name -match \"!SEARCH_PATTERN!\" } | Select-Object -ExpandProperty id) -join ' '"') do (
        set "OTHER_ARGS=!OTHER_ARGS! %%a"
    )
    
    shift
    shift
    goto :process_args
)
if "%~1"=="--name" (
    if "%~2"=="" (
        echo ERROR: query parameter is required for --name
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

set "OTHER_ARGS=!OTHER_ARGS! %~1"
shift
goto :process_args

:after_args
if defined OTHER_ARGS set "run_for_subs=!OTHER_ARGS!"

rem Define color codes
set "GREEN=[92m"
set "RED=[91m"
set "RESET=[0m"
set "BLUE=[94m"

goto :main

:start_test
echo !BLUE!#========================================================================!RESET!
echo !BLUE!# %~1!RESET!
echo !BLUE!#========================================================================!RESET!
exit /b

:end_test_item
exit /b

:end_test
echo.
exit /b

:run_test
if "%~2"=="true" (
    set "result="
    for /f "tokens=*" %%a in ('%~1 2^>^&1') do set "result=%%a"
    if !ERRORLEVEL! equ 0 (
        echo !GREEN!PASS!RESET!	%~1
    ) else (
        echo !RED!FAIL!RESET!	%~1
    )
    if defined result (
        echo !result!
    )
    call :end_test_item
) else (
    echo %~1
)
exit /b

:main
rem load config data from az for listed subs using PowerShell instead of jq
set "configs="
echo Processing subscriptions: !run_for_subs!

for %%x in (!run_for_subs!) do (
    for /f "tokens=*" %%a in ('powershell -Command "$clusters = az aks list --subscription %%x | ConvertFrom-Json; $clusters | Where-Object { $_.name -match \"!AKS_PATTERN!\" } | ForEach-Object { $obj = New-Object PSObject -Property @{name=$_.name; fqdn=$_.fqdn; pfqdn=$_.privateFqdn; sub=$_.id -replace \".*\/subscriptions\/([^\/]*)\/.*\", \"$1\"; rsrc=$_.resourceGroup}; $obj | ConvertTo-Json -Compress } | Write-Output"') do (
        set "configs=!configs! %%a"
    )
)

echo Processing clusters: !configs!

for %%i in (!configs!) do (
    for /f "tokens=*" %%n in ('powershell -Command "(%%i | ConvertFrom-Json).name"') do set "name=%%n"
    for /f "tokens=*" %%f in ('powershell -Command "(%%i | ConvertFrom-Json).fqdn"') do set "fqdn=%%f"
    for /f "tokens=*" %%p in ('powershell -Command "(%%i | ConvertFrom-Json).pfqdn"') do set "pfqdn=%%p"
    for /f "tokens=*" %%s in ('powershell -Command "(%%i | ConvertFrom-Json).sub"') do set "sub=%%s"
    for /f "tokens=*" %%r in ('powershell -Command "(%%i | ConvertFrom-Json).rsrc"') do set "rsrc=%%r"

    call :start_test "!name!"

    call :run_test "nslookup !fqdn!" !INSTALL_FLAG!

    if "!pfqdn!"=="null" (
        if not defined INSTALL_FLAG (
            echo !BLUE!SKIPPED!RESET!	private fqdn not set
            call :end_test_item
        )
    ) else if "!pfqdn!"=="" (
        if not defined INSTALL_FLAG (
            echo !BLUE!SKIPPED!RESET!	private fqdn not set
            call :end_test_item
        )
    ) else (
        call :run_test "nslookup !pfqdn!" !INSTALL_FLAG!
    )

    call :run_test "az account set --subscription !sub!" !INSTALL_FLAG!
    call :run_test "az aks get-credentials --resource-group !rsrc! --name !name! --overwrite-existing" !INSTALL_FLAG!
    call :run_test "kubelogin convert-kubeconfig -l azurecli" !INSTALL_FLAG!
    call :run_test "kubectl get nodes" !INSTALL_FLAG!

    call :end_test "!name!"
)

endlocal
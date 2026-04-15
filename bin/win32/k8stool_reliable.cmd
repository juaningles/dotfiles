@echo off
setlocal EnableDelayedExpansion

:: Initialize variables
set "install_flag="
set "search_pattern="
set "aks_pattern="
set "subscription_ids="
set "timeout_seconds=30"

:: Process command line arguments
:parse_args
if "%~1"=="" goto :after_args
if "%~1"=="--install" (
    set "install_flag=true"
    shift
    goto :parse_args
)
if "%~1"=="--help" (
    call :print_usage
    exit /b 0
)
if "%~1"=="--query" (
    if "%~2"=="" (
        echo ERROR: query parameter is required for --query
        call :print_usage
        exit /b 2
    )
    set "search_pattern=%~2"
    shift
    shift
    goto :parse_args
)
if "%~1"=="--name" (
    if "%~2"=="" (
        echo ERROR: name parameter is required for --name
        call :print_usage
        exit /b 2
    )
    set "aks_pattern=%~2"
    shift
    shift
    goto :parse_args
)
if "%~1:~0,1%"=="-" (
    echo Unknown Option: %1
    call :print_usage
    exit /b 1
)
set "subscription_ids=!subscription_ids! %~1"
shift
goto :parse_args

:print_usage
echo Usage:
echo     %~nx0 [options] [sub [sub ...]]
echo Options:
echo     --install                install credentials
echo     --query query_pattern    query for subscription names that match query_pattern
echo     --name name_pattern      filters for only names that match name_pattern
echo     --help                   display this help message
exit /b

:after_args
:: Define color codes
set "GREEN=[92m"
set "RED=[91m"
set "RESET=[0m"
set "BLUE=[94m"

:: Handle subscription search
if defined search_pattern (
    echo Searching for subscription matching pattern: !search_pattern!
    
    :: Create a temporary PowerShell script to find subscriptions
    echo $pattern = '!search_pattern!'; > find_subs.ps1
    echo $subs = az account list ^| ConvertFrom-Json; >> find_subs.ps1
    echo $matching = $subs ^| Where-Object { $_.name -match $pattern } ^| ForEach-Object { $_.id }; >> find_subs.ps1
    echo if ($matching) { $matching } else { exit 1 } >> find_subs.ps1
    
    :: Execute the PowerShell script
    powershell -ExecutionPolicy Bypass -File find_subs.ps1 > subs.txt
    if !ERRORLEVEL! neq 0 (
        echo !RED!No subscriptions found matching pattern: !search_pattern!!RESET!
        del find_subs.ps1 2>nul
        del subs.txt 2>nul
        call :print_usage
        exit /b 1
    )
    
    echo Matching subscriptions found:
    type subs.txt
    
    :: Read the subscription IDs
    set "subscription_ids="
    for /f "tokens=*" %%s in (subs.txt) do set "subscription_ids=!subscription_ids! %%s"
    
    :: Cleanup
    del find_subs.ps1 2>nul
    del subs.txt 2>nul
)

:: Check if we have any subscriptions
if "!subscription_ids!"=="" (
    echo No subscriptions specified.
    call :print_usage
    exit /b 1
)

echo Working with subscriptions: !subscription_ids!
echo Looking for clusters matching: !aks_pattern!
echo.

:: Process each subscription
set "found_clusters=false"

for %%s in (!subscription_ids!) do (
    echo Processing subscription: %%s
    
    :: Create a temporary PowerShell script to find clusters
    echo $sub = '%%s'; > find_clusters.ps1
    echo $pattern = '!aks_pattern!'; >> find_clusters.ps1
    echo try { >> find_clusters.ps1
    echo     $clusters = az aks list --subscription $sub ^| ConvertFrom-Json; >> find_clusters.ps1
    echo     if ($clusters) { >> find_clusters.ps1
    echo         $filtered = $clusters ^| Where-Object { $_.name -match $pattern }; >> find_clusters.ps1
    echo         $filtered ^| ForEach-Object { >> find_clusters.ps1
    echo             $obj = @{ >> find_clusters.ps1
    echo                 "name" = $_.name; >> find_clusters.ps1
    echo                 "fqdn" = $_.fqdn; >> find_clusters.ps1
    echo                 "pfqdn" = $_.privateFqdn; >> find_clusters.ps1
    echo                 "rsrc" = $_.resourceGroup; >> find_clusters.ps1
    echo                 "sub" = $sub; >> find_clusters.ps1
    echo             }; >> find_clusters.ps1
    echo             $obj ^| ConvertTo-Json -Compress; >> find_clusters.ps1
    echo         } >> find_clusters.ps1
    echo     } >> find_clusters.ps1
    echo } catch { >> find_clusters.ps1
    echo     Write-Error $_.Exception.Message; >> find_clusters.ps1
    echo     exit 1; >> find_clusters.ps1
    echo } >> find_clusters.ps1
    
    :: Execute the PowerShell script
    powershell -ExecutionPolicy Bypass -File find_clusters.ps1 > clusters.json 2>errors.txt
    if !ERRORLEVEL! neq 0 (
        echo !RED!Error accessing subscription: %%s!RESET!
        type errors.txt
        del find_clusters.ps1 2>nul
        del clusters.json 2>nul
        del errors.txt 2>nul
        echo.
        continue
    )
    
    :: Check if we found any clusters
    for /f "usebackq tokens=*" %%j in ("clusters.json") do (
        set "found_clusters=true"
        
        :: Parse cluster details using PowerShell
        echo $clusterJson = '%%j'; > parse_cluster.ps1
        echo $cluster = ConvertFrom-Json $clusterJson; >> parse_cluster.ps1
        echo $cluster.name >> parse_cluster.ps1
        echo $cluster.fqdn >> parse_cluster.ps1
        echo $cluster.pfqdn >> parse_cluster.ps1
        echo $cluster.rsrc >> parse_cluster.ps1
        echo $cluster.sub >> parse_cluster.ps1
        
        powershell -ExecutionPolicy Bypass -File parse_cluster.ps1 > cluster_details.txt
        
        :: Read cluster details
        set /p cluster_name=<cluster_details.txt
        set "line_num=1"
        for /f "usebackq tokens=*" %%l in ("cluster_details.txt") do (
            if !line_num! equ 1 set "name=%%l"
            if !line_num! equ 2 set "fqdn=%%l"
            if !line_num! equ 3 set "pfqdn=%%l"
            if !line_num! equ 4 set "rsrc=%%l"
            if !line_num! equ 5 set "sub=%%l"
            set /a line_num+=1
        )
        
        echo !BLUE!#========================================================================!RESET!
        echo !BLUE!# !name!!RESET!
        echo !BLUE!#========================================================================!RESET!
        
        if defined install_flag (
            call :run_command "nslookup !fqdn!"
            
            if not "!pfqdn!"=="" if not "!pfqdn!"=="null" (
                call :run_command "nslookup !pfqdn!"
            ) else (
                echo !BLUE!SKIPPED!RESET!    private fqdn not set
            )
            
            call :run_command "az account set --subscription !sub!"
            call :run_command "az aks get-credentials --resource-group !rsrc! --name !name! --overwrite-existing"
            call :run_command "kubelogin convert-kubeconfig -l azurecli"
            call :run_command "kubectl get nodes"
        ) else (
            echo nslookup !fqdn!
            
            if not "!pfqdn!"=="" if not "!pfqdn!"=="null" (
                echo nslookup !pfqdn!
            ) else (
                echo !BLUE!SKIPPED!RESET!    private fqdn not set
            )
            
            echo az account set --subscription !sub!
            echo az aks get-credentials --resource-group !rsrc! --name !name! --overwrite-existing
            echo kubelogin convert-kubeconfig -l azurecli
            echo kubectl get nodes
        )
        
        echo.
    )
    
    :: Cleanup
    del find_clusters.ps1 2>nul
    del clusters.json 2>nul
    del parse_cluster.ps1 2>nul
    del cluster_details.txt 2>nul
    del errors.txt 2>nul
)

if not "!found_clusters!"=="true" (
    echo.
    echo !RED!No clusters found matching "!aks_pattern!" in the specified subscriptions.!RESET!
)

exit /b 0

:run_command
setlocal
set "command=%~1"
set "temp_output=command_output.txt"
set "temp_error=command_error.txt"

echo Running with !timeout_seconds!s timeout: !command!

:: Create a temporary script to run the command with timeout
echo @echo off > run_cmd.bat
echo !command! > !temp_output! 2> !temp_error! >> run_cmd.bat
echo exit /b !ERRORLEVEL! >> run_cmd.bat

:: Run the command with a timeout
start /wait /b cmd /c "timeout /t !timeout_seconds! /nobreak > nul & taskkill /f /im cmd.exe /fi "windowtitle eq run_cmd.bat" > nul 2>&1"
start /wait /b cmd /c run_cmd.bat

set "result_code=!ERRORLEVEL!"
if !result_code! equ 0 (
    echo !GREEN!PASS!RESET!    !command!
) else (
    echo !RED!FAIL!RESET!    !command!
)

:: Display output
if exist !temp_output! type !temp_output!
if exist !temp_error! type !temp_error!

:: Cleanup
del run_cmd.bat 2>nul
del !temp_output! 2>nul
del !temp_error! 2>nul

endlocal
exit /b
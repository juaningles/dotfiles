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
:: Create a temporary PowerShell script to do all the work
echo param ( > k8s_helper.ps1
echo     [switch]$Install = $false, >> k8s_helper.ps1
echo     [string]$SearchPattern = "", >> k8s_helper.ps1
echo     [string]$AksPattern = "", >> k8s_helper.ps1
echo     [string[]]$SubscriptionIds = @() >> k8s_helper.ps1
echo ) >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo $GREEN = "[92m" >> k8s_helper.ps1
echo $RED = "[91m" >> k8s_helper.ps1
echo $RESET = "[0m" >> k8s_helper.ps1
echo $BLUE = "[94m" >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo # Get subscriptions by pattern if specified >> k8s_helper.ps1
echo if ($SearchPattern -ne "") { >> k8s_helper.ps1
echo     Write-Host "Searching for subscription matching pattern: $SearchPattern" >> k8s_helper.ps1
echo     $subs = az account list ^| ConvertFrom-Json >> k8s_helper.ps1
echo     $matching = @($subs ^| Where-Object { $_.name -match $SearchPattern } ^| ForEach-Object { $_.id }) >> k8s_helper.ps1
echo     if ($matching.Count -gt 0) { >> k8s_helper.ps1
echo         Write-Host "Matching subscriptions found:" >> k8s_helper.ps1
echo         $matching ^| ForEach-Object { Write-Host $_ } >> k8s_helper.ps1
echo         $SubscriptionIds = $matching >> k8s_helper.ps1
echo     } else { >> k8s_helper.ps1
echo         Write-Host "${RED}No subscriptions found matching pattern: $SearchPattern${RESET}" >> k8s_helper.ps1
echo         exit 1 >> k8s_helper.ps1
echo     } >> k8s_helper.ps1
echo } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo # Check if we have any subscriptions >> k8s_helper.ps1
echo if ($SubscriptionIds.Count -eq 0) { >> k8s_helper.ps1
echo     Write-Host "No subscriptions specified." >> k8s_helper.ps1
echo     exit 1 >> k8s_helper.ps1
echo } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo Write-Host "Working with subscriptions: $($SubscriptionIds -join ', ')" >> k8s_helper.ps1
echo Write-Host "Looking for clusters matching: $AksPattern" >> k8s_helper.ps1
echo Write-Host "" >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo $foundClusters = $false >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo # Function to run command with timeout >> k8s_helper.ps1
echo function Run-CommandWithTimeout { >> k8s_helper.ps1
echo     param( >> k8s_helper.ps1
echo         [string]$Command, >> k8s_helper.ps1
echo         [int]$Timeout = 30 >> k8s_helper.ps1
echo     ) >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo     Write-Host "Running with ${Timeout}s timeout: $Command" >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo     try { >> k8s_helper.ps1
echo         $job = Start-Job -ScriptBlock { >> k8s_helper.ps1
echo             param($cmd) >> k8s_helper.ps1
echo             Invoke-Expression $cmd >> k8s_helper.ps1
echo         } -ArgumentList $Command >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo         $completed = Wait-Job -Job $job -Timeout $Timeout >> k8s_helper.ps1
echo         if ($completed -eq $null) { >> k8s_helper.ps1
echo             Write-Host "${RED}TIMEOUT${RESET} Command exceeded $Timeout seconds" >> k8s_helper.ps1
echo             Stop-Job -Job $job >> k8s_helper.ps1
echo             Remove-Job -Job $job -Force >> k8s_helper.ps1
echo             return >> k8s_helper.ps1
echo         } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo         $result = Receive-Job -Job $job >> k8s_helper.ps1
echo         $exitCode = 0 >> k8s_helper.ps1
echo         if ($job.State -ne "Completed") { $exitCode = 1 } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo         if ($exitCode -eq 0) { >> k8s_helper.ps1
echo             Write-Host "${GREEN}PASS${RESET}    $Command" >> k8s_helper.ps1
echo         } else { >> k8s_helper.ps1
echo             Write-Host "${RED}FAIL${RESET}    $Command" >> k8s_helper.ps1
echo         } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo         if ($result) { >> k8s_helper.ps1
echo             $result >> k8s_helper.ps1
echo         } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo         Remove-Job -Job $job -Force >> k8s_helper.ps1
echo     } catch { >> k8s_helper.ps1
echo         Write-Host "${RED}ERROR${RESET} Failed to execute command: $_" >> k8s_helper.ps1
echo     } >> k8s_helper.ps1
echo } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo # Process each subscription >> k8s_helper.ps1
echo foreach ($sub in $SubscriptionIds) { >> k8s_helper.ps1
echo     Write-Host "" >> k8s_helper.ps1
echo     Write-Host "Processing subscription: $sub" >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo     try { >> k8s_helper.ps1
echo         $clusters = az aks list --subscription $sub ^| ConvertFrom-Json >> k8s_helper.ps1
echo         $filteredClusters = $clusters ^| Where-Object { $_.name -match $AksPattern } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo         foreach ($cluster in $filteredClusters) { >> k8s_helper.ps1
echo             $foundClusters = $true >> k8s_helper.ps1
echo             $name = $cluster.name >> k8s_helper.ps1
echo             $fqdn = $cluster.fqdn >> k8s_helper.ps1
echo             $pfqdn = $cluster.privateFqdn >> k8s_helper.ps1
echo             $rsrc = $cluster.resourceGroup >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo             Write-Host "$BLUE#========================================================================$RESET" >> k8s_helper.ps1
echo             Write-Host "$BLUE# $name$RESET" >> k8s_helper.ps1
echo             Write-Host "$BLUE#========================================================================$RESET" >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo             if ($Install) { >> k8s_helper.ps1
echo                 Run-CommandWithTimeout -Command "nslookup $fqdn" >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo                 if ($pfqdn -and $pfqdn -ne "null") { >> k8s_helper.ps1
echo                     Run-CommandWithTimeout -Command "nslookup $pfqdn" >> k8s_helper.ps1
echo                 } else { >> k8s_helper.ps1
echo                     Write-Host "${BLUE}SKIPPED${RESET}    private fqdn not set" >> k8s_helper.ps1
echo                 } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo                 Run-CommandWithTimeout -Command "az account set --subscription $sub" >> k8s_helper.ps1
echo                 Run-CommandWithTimeout -Command "az aks get-credentials --resource-group $rsrc --name $name --overwrite-existing" >> k8s_helper.ps1
echo                 Run-CommandWithTimeout -Command "kubelogin convert-kubeconfig -l azurecli" >> k8s_helper.ps1
echo                 Run-CommandWithTimeout -Command "kubectl get nodes" >> k8s_helper.ps1
echo             } else { >> k8s_helper.ps1
echo                 Write-Host "nslookup $fqdn" >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo                 if ($pfqdn -and $pfqdn -ne "null") { >> k8s_helper.ps1
echo                     Write-Host "nslookup $pfqdn" >> k8s_helper.ps1
echo                 } else { >> k8s_helper.ps1
echo                     Write-Host "${BLUE}SKIPPED${RESET}    private fqdn not set" >> k8s_helper.ps1
echo                 } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo                 Write-Host "az account set --subscription $sub" >> k8s_helper.ps1
echo                 Write-Host "az aks get-credentials --resource-group $rsrc --name $name --overwrite-existing" >> k8s_helper.ps1
echo                 Write-Host "kubelogin convert-kubeconfig -l azurecli" >> k8s_helper.ps1
echo                 Write-Host "kubectl get nodes" >> k8s_helper.ps1
echo             } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo             Write-Host "" >> k8s_helper.ps1
echo         } >> k8s_helper.ps1
echo     } catch { >> k8s_helper.ps1
echo         Write-Host "${RED}Error accessing subscription: $sub${RESET}" >> k8s_helper.ps1
echo         Write-Host $_.Exception.Message >> k8s_helper.ps1
echo     } >> k8s_helper.ps1
echo } >> k8s_helper.ps1
echo. >> k8s_helper.ps1
echo if (-not $foundClusters) { >> k8s_helper.ps1
echo     Write-Host "" >> k8s_helper.ps1
echo     Write-Host "${RED}No clusters found matching '$AksPattern' in the specified subscriptions.${RESET}" >> k8s_helper.ps1
echo } >> k8s_helper.ps1

:: Set up arguments for the PowerShell script
set "ps_args="
if defined install_flag set "ps_args=!ps_args! -Install"
if defined search_pattern set "ps_args=!ps_args! -SearchPattern !search_pattern!"
if defined aks_pattern set "ps_args=!ps_args! -AksPattern !aks_pattern!"
if defined subscription_ids (
    for %%s in (!subscription_ids!) do set "ps_args=!ps_args! -SubscriptionIds %%s"
)

:: Run the PowerShell script with the arguments
powershell -ExecutionPolicy Bypass -File k8s_helper.ps1 !ps_args!
set exit_code=!ERRORLEVEL!

:: Clean up
del k8s_helper.ps1

exit /b !exit_code!
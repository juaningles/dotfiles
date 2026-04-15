#!/usr/bin/env pwsh
#
# k8stool.ps1 - PowerShell version of k8stool with timeout support
#

# Define color constants for output
$GREEN = "[92m"
$RED = "[91m"
$RESET = "[0m"
$BLUE = "[94m"

# Parse command line arguments
function Parse-Arguments {
    param (
        [Parameter(ValueFromRemainingArguments)]
        $PassedArgs
    )
    
    # Debug input arguments
    Write-Host "Debug: Received arguments: $($PassedArgs -join ', ')"

    $script:installFlag = $false
    $script:searchPattern = ""
    $script:aksPattern = ""
    $script:subscriptionIds = @()

    $i = 0
    while ($i -lt $Args.Count) {
        switch ($Args[$i]) {
            "--install" {
                $script:installFlag = $true
                $i++
            }
            "--help" {
                Print-Usage
                exit 0
            }
            "--query" {
                if ($i + 1 -ge $Args.Count) {
                    Write-Host "ERROR: query parameter is required for --query"
                    Print-Usage
                    exit 2
                }
                $script:searchPattern = $Args[$i + 1]
                $i += 2
            }
            "--name" {
                if ($i + 1 -ge $Args.Count) {
                    Write-Host "ERROR: name parameter is required for --name"
                    Print-Usage
                    exit 2
                }
                $script:aksPattern = $Args[$i + 1]
                $i += 2
            }
            default {
                if ($Args[$i].StartsWith("-")) {
                    Write-Host "Unknown Option: $($Args[$i])"
                    Print-Usage
                    exit 1
                }
                $script:subscriptionIds += $Args[$i]
                $i++
            }
        }
    }

    # If search pattern is provided, find matching subscriptions
    if ($script:searchPattern) {
        Write-Host "Searching for subscription matching pattern: $($script:searchPattern)"
        $subs = az account list | ConvertFrom-Json
        $matchingSubs = $subs | Where-Object { $_.name -match $script:searchPattern } | Select-Object -ExpandProperty id
        
        if ($matchingSubs) {
            Write-Host "Matching subscriptions found:"
            $matchingSubs | ForEach-Object { Write-Host $_ }
            $script:subscriptionIds = $matchingSubs
        }
        else {
            Write-Host "$($RED)No subscriptions found matching pattern: $($script:searchPattern)$($RESET)"
            Print-Usage
            exit 1
        }
    }

    # Check if we have any subscriptions to work with
    if ($script:subscriptionIds.Count -eq 0) {
        Write-Host "No subscriptions specified."
        Print-Usage
        exit 1
    }
}

# Print usage information
function Print-Usage {
    $scriptName = [System.IO.Path]::GetFileName($MyInvocation.ScriptName)
    Write-Host "Usage:"
    Write-Host "    $scriptName [options] [sub [sub ...]]"
    Write-Host "Options:"
    Write-Host "    --install                install credentials"
    Write-Host "    --query query_pattern    query for subscription names that match query_pattern"
    Write-Host "    --name name_pattern      filters for only names that match name_pattern"
    Write-Host "    --help                   display this help message"
}

# Run a command with timeout
function Run-CommandWithTimeout {
    param(
        [string]$Command,
        [int]$TimeoutSeconds = 30
    )

    Write-Host "Running with ${TimeoutSeconds}s timeout: $Command"
    
    # Create a script block from the command string
    $scriptBlock = [ScriptBlock]::Create($Command)
    
    try {
        # Start a job that runs the command
        $job = Start-Job -ScriptBlock $scriptBlock
        
        # Wait for the job to complete with a timeout
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        
        if ($completed -eq $null) {
            # Job timed out
            Stop-Job -Job $job
            Write-Host "$($RED)TIMEOUT$($RESET) Command exceeded $TimeoutSeconds seconds"
            return $false
        }
        
        # Retrieve the output from the job
        $result = Receive-Job -Job $job
        
        # Check exit code
        if ($job.State -eq "Completed") {
            Write-Host "$($GREEN)PASS$($RESET) $Command"
            if ($result) {
                $result | ForEach-Object { Write-Host $_ }
            }
            return $true
        } else {
            Write-Host "$($RED)FAIL$($RESET) $Command"
            if ($result) {
                $result | ForEach-Object { Write-Host $_ }
            }
            return $false
        }
    }
    catch {
        Write-Host "$($RED)ERROR$($RESET) Failed to execute command: $_"
        return $false
    }
    finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

# Start a test block for a cluster
function Start-Test {
    param([string]$TestName)
    
    Write-Host "$($BLUE)#========================================================================$($RESET)"
    Write-Host "$($BLUE)# $TestName$($RESET)"
    Write-Host "$($BLUE)#========================================================================$($RESET)"
}

# End a test block
function End-Test {
    Write-Host ""
}

# Run a test command or display command
function Run-Test {
    param(
        [string]$Command,
        [bool]$Execute = $false
    )
    
    if ($Execute) {
        Run-CommandWithTimeout -Command $Command
    } else {
        Write-Host $Command
    }
}

# Main function
function Main {
    # Parse the command line arguments
    Parse-Arguments $args
    
    Write-Host "Working with subscriptions: $($script:subscriptionIds -join ', ')"
    Write-Host "Looking for clusters matching: $($script:aksPattern)"
    Write-Host ""
    
    $foundClusters = $false
    
    # Process each subscription
    foreach ($sub in $script:subscriptionIds) {
        Write-Host "Processing subscription: $sub"
        
        try {
            # List AKS clusters and filter by name
            $azCommand = "az aks list --subscription $sub"
            $clusters = Invoke-Expression $azCommand | ConvertFrom-Json
            
            if ($clusters) {
                $filteredClusters = $clusters | Where-Object { $_.name -match $script:aksPattern }
                
                foreach ($cluster in $filteredClusters) {
                    $foundClusters = $true
                    $name = $cluster.name
                    $fqdn = $cluster.fqdn
                    $pfqdn = $cluster.privateFqdn
                    $rsrc = $cluster.resourceGroup
                    $subId = $sub
                    
                    Start-Test -TestName $name
                    
                    if ($script:installFlag) {
                        Run-Test -Command "nslookup $fqdn" -Execute $true
                        
                        if ($pfqdn -and $pfqdn -ne "null") {
                            Run-Test -Command "nslookup $pfqdn" -Execute $true
                        } else {
                            Write-Host "$($BLUE)SKIPPED$($RESET) private fqdn not set"
                        }
                        
                        Run-Test -Command "az account set --subscription $subId" -Execute $true
                        Run-Test -Command "az aks get-credentials --resource-group $rsrc --name $name --overwrite-existing" -Execute $true
                        Run-Test -Command "kubelogin convert-kubeconfig -l azurecli" -Execute $true
                        Run-Test -Command "kubectl get nodes" -Execute $true
                    } else {
                        Run-Test -Command "nslookup $fqdn" -Execute $false
                        
                        if ($pfqdn -and $pfqdn -ne "null") {
                            Run-Test -Command "nslookup $pfqdn" -Execute $false
                        } else {
                            Write-Host "$($BLUE)SKIPPED$($RESET) private fqdn not set"
                        }
                        
                        Run-Test -Command "az account set --subscription $subId" -Execute $false
                        Run-Test -Command "az aks get-credentials --resource-group $rsrc --name $name --overwrite-existing" -Execute $false
                        Run-Test -Command "kubelogin convert-kubeconfig -l azurecli" -Execute $false
                        Run-Test -Command "kubectl get nodes" -Execute $false
                    }
                    
                    End-Test
                }
            }
        } catch {
            Write-Host "$($RED)Error accessing subscription:$($RESET) $_"
        }
    }
    
    if (-not $foundClusters) {
        Write-Host ""
        Write-Host "$($RED)No clusters found matching '$($script:aksPattern)' in the specified subscriptions.$($RESET)"
    }
}

# Entry point - call the main function with all script arguments
Main $args
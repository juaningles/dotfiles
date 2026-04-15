@echo off
setlocal enabledelayedexpansion

REM Default values
set "imagename="
set "DistroName=mydistro"
set "username=%USERNAME%"
set "storage_path_base=C:\wsl-storage"
set "show_help=0"
set "temp_tar_path=%TEMP%\wsl_import_temp.tar"

REM Parse command line arguments
:ParseArgs
IF "%~1"=="" GOTO ArgsParsed
IF /I "%~1"=="/h" set show_help=1& GOTO Usage
IF /I "%~1"=="-h" set show_help=1& GOTO Usage
IF /I "%~1"=="--help" set show_help=1& GOTO Usage
IF /I "%~1"=="/?" set show_help=1& GOTO Usage

IF /I "%~1"=="/image" (
    set "imagename=%~2"
    SHIFT
    SHIFT
    GOTO ParseArgs
)
IF /I "%~1"=="/distro" (
    set "DistroName=%~2"
    SHIFT
    SHIFT
    GOTO ParseArgs
)
IF /I "%~1"=="/storage" (
    set "storage_path_base=%~2"
    SHIFT
    SHIFT
    GOTO ParseArgs
)
IF /I "%~1"=="/user" (
    set "username=%~2"
    SHIFT
    SHIFT
    GOTO ParseArgs
)

echo Unrecognized argument: %1
set show_help=1
GOTO Usage

:ArgsParsed

REM Construct full storage path
set "storage_path=%storage_path_base%\%DistroName%"

IF "%show_help%"=="1" GOTO Usage

REM Check required parameters
IF "%imagename%"=="" (
    echo Error: Image name is required. Use /image <imagename>.
    GOTO Usage
)

REM Check prerequisites
where podman >nul 2>nul
IF ERRORLEVEL 1 (
    echo Error: 'podman' command not found. Please ensure podman Desktop is installed and running.
    exit /b 1
)
where wsl >nul 2>nul
IF ERRORLEVEL 1 (
    echo Error: 'wsl' command not found. Please ensure WSL is installed.
    exit /b 1
)

echo --- Configuration ---
echo podman Image: %imagename%
echo WSL Distro Name: %DistroName%
echo WSL Storage Path: %storage_path%
echo WSL Username: %username%
echo Temporary Export Path: %temp_tar_path%
echo ---------------------
echo.

REM --- Start Process ---

REM Check if distro already exists
REM Use wsl --list --quiet and findstr exact match
echo DEBUG: Checking for existing distro '%DistroName%'...
echo DEBUG: Running 'wsl.exe --list --quiet'...
wsl.exe --list --quiet > temp_wsl_list.txt
echo DEBUG: Output of wsl --list --quiet:
 type temp_wsl_list.txt
echo DEBUG: Running 'findstr /X /C:"%DistroName%" temp_wsl_list.txt'...
findstr /X /C:"%DistroName%" temp_wsl_list.txt > nul
set find_result=%ERRORLEVEL%
echo DEBUG: findstr ERRORLEVEL = %find_result%
del temp_wsl_list.txt

IF %find_result% EQU 0 (
    echo Error: WSL distribution '%DistroName%' already exists. Please choose a different name or unregister the existing one using 'wsl --unregister %DistroName%'.
    exit /b 1
) else (
    echo DEBUG: Distro '%DistroName%' not found by findstr. Proceeding...
)

echo [1/8] Pulling podman image '%imagename%'...
podman pull %imagename%
IF ERRORLEVEL 1 (
    echo Error: Failed to pull podman image '%imagename%'. Check the image name and podman connectivity.
    exit /b 1
)
echo Pull successful.
echo.

set "temp_container_name=wsl_import_%DistroName%_%RANDOM%"
echo [2/8] Starting temporary container '%temp_container_name%' from image '%imagename%'...
podman run -d --rm --name %temp_container_name% %imagename% tail -f /dev/null
IF ERRORLEVEL 1 (
    echo Error: Failed to start temporary podman container '%temp_container_name%'.
    exit /b 1
)
echo Temporary container started.
echo.

echo [3/8] Exporting container '%temp_container_name%' to '%temp_tar_path%'...
podman export %temp_container_name% > "%temp_tar_path%"
IF ERRORLEVEL 1 (
    echo Error: Failed to export podman container '%temp_container_name%'. Check permissions and available disk space in '%TEMP%'.
    podman stop %temp_container_name% > nul
    exit /b 1
)
echo Export successful.
echo.

echo [4/8] Stopping temporary container '%temp_container_name%'...
podman stop %temp_container_name% > nul
IF ERRORLEVEL 1 (
    echo Warning: Failed to stop temporary podman container '%temp_container_name%'. It might have already stopped or encountered an issue.
) else (
    echo Temporary container stopped.
)
echo.

echo [5/8] Importing '%temp_tar_path%' into WSL as '%DistroName%' at '%storage_path%'...
REM Ensure storage directory exists
if not exist "%storage_path_base%" mkdir "%storage_path_base%"
if not exist "%storage_path%" mkdir "%storage_path%"
wsl.exe --import %DistroName% "%storage_path%" "%temp_tar_path%" --version 2
IF ERRORLEVEL 1 (
    echo Error: Failed to import image into WSL as '%DistroName%'. Check WSL version, permissions, and disk space for '%storage_path%'.
    del "%temp_tar_path%" > nul 2>nul
    exit /b 1
)
echo Import successful. Deleting temporary tar file...
del "%temp_tar_path%" > nul 2>nul
echo.

echo [6/8] Detecting distribution type and running initial setup in '%DistroName%'...
REM Check for Debian/Ubuntu marker file
echo checking
wsl.exe -d %DistroName% --user root test -f /etc/debian_version
IF ERRORLEVEL 0 (
    echo Detected Debian-based distribution. Using apt-get...
    wsl.exe -d %DistroName% --user root apt-get update
    IF ERRORLEVEL 1 (
        echo Warning: 'apt-get update' failed in '%DistroName%'. Network issues or base image configuration might be the cause. Continuing...
    ) else (
        wsl.exe -d %DistroName% --user root apt-get install -y sudo
        IF ERRORLEVEL 1 (
            echo Warning: Failed to install 'sudo' using apt-get in '%DistroName%'.
        ) else (
			wsl.exe -d %DistroName% --user root usermod -aG sudo %username%
            echo "Initial setup commands with apt executed."
        )
    )
) else (
    REM Check for Alpine marker file
    wsl.exe -d %DistroName% --user root test -f /etc/alpine-release
    IF ERRORLEVEL 0 (
        echo Detected Alpine-based distribution. Using apk...
        wsl.exe -d %DistroName% --user root apk update
        IF ERRORLEVEL 1 (
            echo Warning: 'apk update' failed in '%DistroName%'. Network issues or base image configuration might be the cause. Continuing...
        ) else (
            wsl.exe -d %DistroName% --user root apk add sudo
            IF ERRORLEVEL 1 (
                echo Warning: Failed to install 'sudo' using apk in '%DistroName%'.
            ) else (
				wsl.exe -d %DistroName% --user root usermod -aG sudo %username%
                echo Initial setup commands with apk executed.
            )
        )
    ) else (
        echo Warning: Could not reliably detect distribution type= Debian/Alpine. Skipping package manager setup. Sudo might not be available.
    )
)

echo [7/8] Creating user '%username%' and adding to sudo group in '%DistroName%'...
wsl.exe -d %DistroName% --user root adduser --disabled-password --gecos "" %username%
IF ERRORLEVEL 1 (
    echo Error: Failed to create user '%username%' in '%DistroName%'.
    exit /b 1
)
REM Add user to the 'wheel' group for sudo on Alpine, 'sudo' group for Debian
wsl.exe -d %DistroName% --user root test -f /etc/alpine-release
IF ERRORLEVEL 0 (
    echo Adding user to 'wheel' group Alpine...
    wsl.exe -d %DistroName% --user root adduser %username% wheel
) else (
    echo Adding user to 'sudo' group Debian/Other...
    wsl.exe -d %DistroName% --user root adduser %username% sudo
)

IF ERRORLEVEL 1 (
    echo Warning: Failed to add user '%username%' to the appropriate sudo group in '%DistroName%'. User created but may lack sudo privileges.
) else (
    echo User '%username%' created and added to sudo group.
)
echo.

echo [8/8] Setting default user for '%DistroName%' to '%username%'...
REM Create /etc/wsl.conf to set the default user
echo [user] > temp_wsl.conf
echo default=%username% >> temp_wsl.conf
REM Need to copy the file into the WSL instance using stdin redirection
wsl.exe -d %DistroName% --user root sh -c "cat > /etc/wsl.conf" < temp_wsl.conf
del temp_wsl.conf
IF ERRORLEVEL 1 (
    echo Warning: Failed to set default user '%username%' using /etc/wsl.conf. You might need to log in as root initially.
) else (
    echo Default user set.
	wsl.exe --terminate %DistroName%
)
echo.

echo --- Success ---
echo WSL distribution '%DistroName%' created successfully from podman image '%imagename%'.
echo Default user is '%username%'.
echo You can start it using: wsl -d %DistroName%
echo -------------
goto :eof

:Usage
@echo
@echo Imports a podman image into WSL as a new distribution.
@echo .
@echo Usage: %~n0 /image <podman_image_name> [options]
@echo .
@echo Required:
@echo   /image <name>    Specifies the podman image to import (e.g., ubuntu:latest).
@echo .
@echo Options:
@echo   /distro <name>   Specifies the name for the new WSL distribution.
@echo                    (Default: mydistro)
@echo   /storage <path>  Specifies the base directory to store the WSL disk image.
@echo                    The distro name will be appended as a subdirectory.
@echo                    (Default: C:\wsl-storage)
@echo   /user <name>     Specifies the default username to create within the WSL distro.
@echo                    (Default: current Windows user '%USERNAME%')
@echo   /h, /?, --help   Displays this help message.
@echo .
@echo Example:
@echo   %~n0 /image myapp/dev:latest /distro MyDevEnv /user devuser
@echo .
exit /b 1

:eof
endlocal


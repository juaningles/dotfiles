@echo off

REM write a windows 11 .cmd script that
REM accepts an optional name of a docker container and optional parameters '--kill' or '--stop" (can be in any order)
REM if no name is given, assume a name of 'devnode'

REM if '--kill' is given , then execute docker command to kill that container name, if it is running,  and then stop processing the script
REM if '--stop' is given, execute docker command to "stop" that container, if it is running, and then stop processing the script

REM if neither ''--kill" or "--stop" is given:
REM check to see if that container is running. If not, launch it into the background with "docker run"
REM Then connect to it with "docker exec" command

setlocal
set DOCKER_CLI_HINTS=false

:: Default container name
set CONTAINER_NAME=devnode
set CONTAINER_IMAGE=juaningles/devnode:full

:parse_args
if "%1"=="" (
    goto run_container
)

if "%1"=="--pull" (
    set ACTION=pull
    shift
    goto check_name
)


if "%1"=="--image" (
    set CONTAINER_IMAGE="%2"
    shift
    shift
    goto check_name
)

if "%1"=="--stop" (
    set ACTION=stop
    shift
    goto check_name
)

if "%1"=="--kill" (
    set ACTION=kill
    shift
    goto check_name
)


if "%1"=="--rm" (
    set ACTION=remove
    shift
    goto check_name
)
set CONTAINER_NAME=%1 & shift
goto parse_args

@REM :: Check for arguments
@REM :parse_args
@REM if "%1"=="" goto run_container
@REM if "%1"=="--kill" set ACTION=kill & shift & goto check_name
@REM if "%1"=="--stop" set ACTION=stop & shift & goto check_name
@REM if "%1"=="--pull" set ACTION=pull & shift & goto check_name
@REM set CONTAINER_NAME=%1 & shift
@REM goto parse_args

:check_name
if "%1"=="" (
    goto perform_action
)

set CONTAINER_NAME=%1 & shift
goto perform_action

:perform_action
if "%ACTION%"=="kill" (
    echo Killing
    docker kill %CONTAINER_NAME%
    goto end
)
if "%ACTION%"=="stop" (
    echo Stopping
    docker stop %CONTAINER_NAME%
    goto end
)
if "%ACTION%"=="pull" (
    echo Pulling
    docker pull %CONTAINER_IMAGE%
    goto end
)
if "%ACTION%"=="remove" (
    echo Removing
    docker rmi %CONTAINER_IMAGE%
    goto end
)

:run_container
docker ps | findstr /i /c:"%CONTAINER_NAME%" > nul
if errorlevel 1 (
    docker run -it --privileged --restart always -v "C:/:/mnt/c" -v "C:/wsl-storage/devnode/home:/root" -v "C:/wsl-storage/devnode/bin:/usr/local/bin" --name %CONTAINER_NAME% %CONTAINER_IMAGE% bash
    if errorlevel 1 (
        docker exec -it %CONTAINER_NAME% /bin/bash
    )
    goto end
)
docker exec -it %CONTAINER_NAME% /bin/bash

:end
endlocal
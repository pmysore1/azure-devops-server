[CmdletBinding()]
param(
    [string] $SqlInstance,
    [string] $userName,
    [string] $password
)

$ErrorActionPreference = 'Stop'

# TFS 2017 Update 2
$TfsDownloadUrl = 'https://go.microsoft.com/fwlink/?LinkId=2089023'
$InstallDirectory = 'C:\Program Files\Azure DevOps Server 2019'
$InstallKey = 'HKLM:\SOFTWARE\Microsoft\DevDiv\tfs\Servicing\15.0\serverCore'
$ssmsUrl = 'https://aka.ms/ssmsfullsetup'


$PsToolsDownloadUrl = 'https://download.sysinternals.com/files/PSTools.zip'

# Checks if TFS is installed, if not downloads and runs the web installer
function Ensure-TfsInstalled()
{
    # Check if TFS is already installed
    $tfsInstalled = $false

    if(Test-Path $InstallKey)
    {
        $key = Get-Item $InstallKey
        $value = $key.GetValue("Install", $null)

        if(($value -ne $null) -and ($value -eq 1))
        {
            $tfsInstalled = $true
        }
    }

    if(-not $tfsInstalled)
    {
        Write-Verbose "Installing TFS using web installer"

        # Download TFS install to a temp folder, then run it
        $parent = [System.IO.Path]::GetTempPath()
        [string] $name = [System.Guid]::NewGuid()
        [string] $fullPath = Join-Path $parent $name

        try 
        {
            New-Item -ItemType Directory -Path $fullPath
            $serverLocation = Join-Path $fullPath 'tfsserver.exe'

            Invoke-WebRequest -UseBasicParsing -Uri $TfsDownloadUrl -OutFile $serverLocation
            
            $process = Start-Process -FilePath $serverLocation -ArgumentList '/quiet' -PassThru
            $process.WaitForExit()
        }
        finally 
        {
            Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else
    {
        Write-Verbose "TFS is already installed"
    }
}
function installSQLManagementStudio()
{
    # Set file and folder path for SSMS installer .exe
    $folderpath="c:\windows\temp"
    $filepath="$folderpath\SSMS-Setup-ENU.exe"
    
    #If SSMS not present, download
    if (!(Test-Path $filepath)) {
        write-host "Downloading SQL Server 2016 SSMS..."
        $URL = "https://download.microsoft.com/download/3/1/D/31D734E0-BFE8-4C33-A9DE-2392808ADEE6/SSMS-Setup-ENU.exe"
        $clnt = New-Object System.Net.WebClient
        $clnt.DownloadFile($url,$filepath)
        Write-Host "SSMS installer download complete" -ForegroundColor Green
        
    }
    else {
    
        write-host "Located the SQL SSMS Installer binaries, moving on to install..."
    }
    
    # start the SSMS installer
    write-host "Beginning SSMS 2016 install..." -nonewline
    $Parms = " /Install /Quiet /Norestart /Logs log.txt"
    $Prms = $Parms.Split(" ")
    & "$filepath" $Prms | Out-Null
    Write-Host "SSMS installation complete" -ForegroundColor Green
}

function Download-PsTools()
{
    [string] $downloadPath = Join-Path $PSScriptRoot "PSTools.zip"
    [string] $targetFolder = Join-Path $PSScriptRoot "PsTools"
    
    if (!(Test-Path $targetFolder))
    {
        try 
        {
            Invoke-WebRequest -UseBasicParsing -Uri $PsToolsDownloadUrl -OutFile $downloadPath
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadPath, $targetFolder)
        }
        finally
        {
            Remove-Item $downloadPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Configure-TfsRemoteSql()
{
    # Run tfsconfig to do the unattend install
    $path = Join-Path $InstallDirectory '\tools\tfsconfig.exe'

    Write-Verbose "Running tfsconfig..."

    # The System account running this script for the VM Extension is not allowed to impersonate, 
    # so we can't use Start-Process with the -Credential parameter to run setup as a domain user with access to SQL
    # Instead we'll use psexec.exe from the PsTools Suite (https://docs.microsoft.com/en-us/sysinternals/downloads/pstools)
    & $PSScriptRoot\PsTools\psexec.exe -h -accepteula -u $userName -p $password "$path" unattend /configure /type:Standard /inputs:"SqlInstance=$SqlInstance"
    
    if($LASTEXITCODE)
    {
        throw "tfsconfig.exe failed with exit code $LASTEXITCODE . Check the TFS logs for more information"
    }
}

Ensure-TfsInstalled
Download-PsTools
#Configure-TfsRemoteSql
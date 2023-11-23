# Windows ISO Debloater Script

## Overview

This PowerShell script automates the debloating process for Windows ISO images. It removes specified packages, features, and performs various system tweaks to create a streamlined Windows installation.

## Prerequisites

- Windows operating system
- PowerShell
- Administrator privileges

## Tested Versions

This script has been tested with:

- Windows 10 version 22H2 (Build 19045.3757)
- Windows 11 version 23H2 (Build 22631.2787)

## Usage

1. Download and Mount the windows ISO
2. Launch PowerShell as **ADMINISTRATOR** and execute the following commands
```{powershell}
Set-ExecutionPolicy Unrestricted -Force
iwr -useb https://raw.githubusercontent.com/itsNileshHere/Windows-ISO-Debloater/main/download.ps1 | iex
```
*Alternatively, you can manually download the script from [here](https://github.com/itsNileshHere/Windows-ISO-Debloater/releases/latest) and execute it using PowerShell with **ADMINISTRATOR** privileges.*

3. The ISO will be generated in the same directory where the script is located.
4. To whitelist a package, simply comment out its name in the script.

## Customization

You can customize the script by modifying the following sections of the script:

- Packages to remove
- Features to remove
- Registry tweaks

## Oscdimg
The provided "oscdimg.exe", used to generate the ISO, is downloaded from Microsoft's website. If you have any doubts, you can download it using the following steps:

1. Download the "Windows ADK" Package from [Microsoft](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install).
2. Run the setup. During installation, only check the "Deployment Tools" option and continue the installation.
3. After installing, navigate to "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg". The "oscdimg.exe" file will be located there.
4. Copy the file and paste it alongside the script."

---

**Note:** This script modifies the Windows ISO. Use it at your own risk, and ensure you have a backup before running.


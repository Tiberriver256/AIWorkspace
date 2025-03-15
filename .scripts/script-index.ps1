# Import the module
Import-Module "$PSScriptRoot/MyUtilities" -Force

Get-Command -Module MyUtilities | Get-Help | select Name,Synopsis | fl
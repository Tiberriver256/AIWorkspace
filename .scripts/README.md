# PowerShell Scripts

This folder contains useful PowerShell scripts and modules to help with various automation tasks.

## Getting Started

1. Run `script-index.ps1` to import the utilities module and see all available commands:
   ```powershell
   .\script-index.ps1
   ```

2. Set up your Azure DevOps connection:
   ```powershell
   Invoke-SetupAzDOConnection
   ```

## Available Modules

- `MyUtilities`: Core utility functions for common tasks

## Common Tasks

- List available commands: `.\script-index.ps1`
- Connect to Azure DevOps: `Invoke-SetupAzDOConnection`

## Adding New Scripts

Place new script modules in the `MyUtilities` folder and they will be imported automatically when running `script-index.ps1`.
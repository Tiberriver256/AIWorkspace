# AIWorkspace

This repository contains my personal AI-assisted workspace with PowerShell utilities and scripts, primarily focused on Azure DevOps operations and automation.

## Overview

This workspace provides a collection of PowerShell scripts and modules to help AI assistants interact with my development environment, particularly for Azure DevOps operations. The scripts enable AI to perform tasks like:

- Connecting to Azure DevOps organizations
- Retrieving information about projects, teams, and repositories
- Analyzing pipeline status and migration progress
- Searching code and work items
- Visualizing repository structures

## Repository Structure

```
.
├── .gitignore               # Git ignore file
├── .cursor/                 # Cursor editor configuration
├── .github/                 # GitHub configuration
├── .scripts/                # PowerShell scripts and modules
│   ├── README.md            # Scripts documentation
│   ├── script-index.ps1     # Script to import modules and list commands
│   └── MyUtilities/         # PowerShell module with Azure DevOps utilities
│       ├── MyUtilities.psd1 # Module manifest
│       ├── MyUtilities.psm1 # Module loader
│       ├── Private/         # Internal module functions
│       └── Public/          # Exported module functions
└── task-management/         # Task management files
    ├── doing.md             # Tasks in progress
    ├── done.md              # Completed tasks
    └── todo.md              # Pending tasks
```

## Getting Started

1. Clone this repository to your local machine
2. Navigate to the `.scripts` folder
3. Run the script-index.ps1 to import all utilities:

```powershell
cd .scripts
.\script-index.ps1
```

4. Set up your Azure DevOps connection:

```powershell
Invoke-SetupAzDOConnection
```

## Available Commands

The MyUtilities module provides various commands for Azure DevOps operations:

- **Connect-AzDO**: Connect to an Azure DevOps organization
- **Get-AzDOOrganizations**: List all accessible Azure DevOps organizations
- **Get-AzDOProjects**: List projects in an organization
- **Get-AzDOTeams**: List teams in a project
- **Get-AzDOTeamActivity**: Get activity statistics for a team
- **Get-AzDOPipelineMigrationStatus**: Track YAML pipeline migration progress
- **Get-AzDOPipelineFailureInfo**: Analyze pipeline failures
- **Show-Tree**: Display folder structure as a tree
- **Search-AzDOCode**: Search code in Azure DevOps repositories
- **Search-AzDOWorkItems**: Search work items in Azure DevOps

## Examples

### Connect to Azure DevOps and explore projects

```powershell
# Connect to Azure DevOps organization
Connect-AzDO -OrgName "MyOrganization" -ProjectName "MyProject"

# List all projects in the organization
Get-AzDOProjects

# List all teams in the current project
Get-AzDOTeams
```

### Analyze pipeline migration progress

```powershell
# Get migration status for all organizations
Get-AzDOPipelineMigrationStatus

# Get summary status for specific organizations
Get-AzDOPipelineMigrationStatus -OrgNames "MyOrg1", "MyOrg2" -Summary
```

### Explore repository structure

```powershell
# Show the file tree of a repository
Show-AzDORepositoryTree -RepositoryName "MyRepo"
```

## Task Management

The workspace includes a task management system in the `task-management` folder:

- **todo.md**: List of pending tasks
- **doing.md**: Tasks currently in progress
- **done.md**: Completed tasks

## Contributing

This is a personal workspace, but suggestions for improvements are welcome.

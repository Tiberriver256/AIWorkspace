function Get-AzDOProjects {
    <#
    .SYNOPSIS
        Lists all projects in the connected Azure DevOps organization.

    .DESCRIPTION
        This function lists all projects in the currently connected Azure DevOps organization.
        If not connected to an organization, it can attempt to connect first.
        It can provide either basic information or detailed project properties.

    .PARAMETER OrgName
        Optional. The name of the Azure DevOps organization to connect to if not already connected.

    .PARAMETER Detailed
        Switch to show detailed project information including:
        - Project ID
        - Description
        - Source Control
        - Process Template
        - Visibility
        - State
        - Creation Details
        - Last Update
        - Additional Properties

    .EXAMPLE
        Get-AzDOProjects
        Lists all projects in the currently connected organization with basic information.

    .EXAMPLE
        Get-AzDOProjects -OrgName "MyOrganization"
        Connects to MyOrganization and then lists all projects.

    .EXAMPLE
        Get-AzDOProjects -Detailed
        Lists all projects with detailed information including source control, process template, etc.

    .NOTES
        This function requires:
        - VSTeam PowerShell module
        - Active connection to Azure DevOps (use Connect-AzDO first)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$OrgName,
        
        [Parameter(Mandatory = $false)]
        [switch]$Detailed
    )

    try {
        # Connect to organization if specified
        if ($OrgName) {
            & "$PSScriptRoot/../Private/Invoke-SetupAzDOConnection.ps1" -OrgName $OrgName
        }

        # Check if connected to an organization
        $info = Get-VSTeamInfo
        if (-not $info.Account) {
            throw "Not connected to any Azure DevOps organization. Use -OrgName parameter or run Connect-AzDO first."
        }
        
        Write-Verbose "Getting projects from organization '$($info.Account)'..."
        
        # Get projects
        if ($Detailed) {
            $projects = Get-VSTeamProject | Select-Object *
        } else {
            $projects = Get-VSTeamProject | Select-Object Name, Description
        }
        
        if (-not $projects -or $projects.Count -eq 0) {
            Write-Warning "No projects found in organization '$($info.Account)'."
            return
        }
        
        Write-Verbose "Found $($projects.Count) projects in organization '$($info.Account)'"
        
        # Format output based on detail level
        if ($Detailed) {
            $projects | Format-List
        } else {
            $projects | Format-Table -AutoSize
        }
        
        return $projects
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
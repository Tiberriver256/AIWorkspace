function Get-AzDOTeams {
    <#
    .SYNOPSIS
        Lists all teams in an Azure DevOps project.

    .DESCRIPTION
        This function retrieves all teams defined in a specified Azure DevOps project.
        It can provide either basic information or detailed team properties.

    .PARAMETER ProjectName
        Optional. The name of the project to list teams for. If not specified, uses the default project.

    .PARAMETER OrgName
        Optional. The name of the Azure DevOps organization to connect to if not already connected.

    .PARAMETER Detailed
        Switch to display detailed team information including:
        - Team ID
        - Description
        - Project Details
        - Team Settings
        - Team Members Count
        - Additional Properties

    .EXAMPLE
        Get-AzDOTeams -ProjectName "MyProject"
        Lists all teams in the MyProject project with basic information.

    .EXAMPLE
        Get-AzDOTeams -ProjectName "MyProject" -OrgName "MyOrganization"
        Connects to MyOrganization, then lists all teams in the MyProject project.

    .EXAMPLE
        Get-AzDOTeams -Detailed
        Lists detailed information about teams in the default project.

    .NOTES
        This function requires:
        - VSTeam PowerShell module
        - Active connection to Azure DevOps (use Connect-AzDO first)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ProjectName,
        
        [Parameter(Mandatory = $false)]
        [string]$OrgName,
        
        [Parameter(Mandatory = $false)]
        [switch]$Detailed
    )

    try {
        # Connect to organization if specified
        if ($OrgName) {
            & "$PSScriptRoot/../Private/Invoke-SetupAzDOConnection.ps1" -OrgName $OrgName -ProjectName $ProjectName
        }
        elseif ($ProjectName) {
            # Set project if organization is already connected
            Set-VSTeamDefaultProject -Project $ProjectName
            Write-Verbose "Set $ProjectName as default project"
        }

        # Get the info to check connection
        $info = Get-VSTeamInfo
        
        if (-not $info.Account) {
            throw "Not connected to any Azure DevOps organization. Use -OrgName parameter or run Connect-AzDO first."
        }
        
        if ((-not $ProjectName) -and (-not $info.DefaultProject)) {
            throw "No project specified and no default project set. Use -ProjectName parameter."
        }
        
        # Get all teams in the project
        $project = if ($ProjectName) { $ProjectName } else { $info.DefaultProject }
        Write-Verbose "Getting teams for project '$project'..."
        
        if ($Detailed) {
            $teams = Get-VSTeam -ProjectName $project | Select-Object *
        } else {
            $teams = Get-VSTeam -ProjectName $project | Select-Object Name, Description
        }
        
        if (-not $teams -or $teams.Count -eq 0) {
            Write-Warning "No teams found in project '$project'."
            return
        }
        
        Write-Verbose "Found $($teams.Count) teams in project '$project'"
        
        # Format output based on detail level
        if ($Detailed) {
            $teams | Format-List
        } else {
            $teams | Format-Table -AutoSize
        }
        
        return $teams
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
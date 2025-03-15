function Get-AzDOTeamActivity {
    <#
    .SYNOPSIS
        Retrieves recent activity for a team in Azure DevOps.

    .DESCRIPTION
        This function provides a comprehensive view of a team's activities in Azure DevOps,
        including work items created and updated within a specified time period.
        The function returns detailed information about each activity and provides a summary.

    .PARAMETER TeamName
        The name of the team to get activity for.

    .PARAMETER ProjectName
        Optional. The project name. If not specified, uses the default project.

    .PARAMETER OrgName
        Optional. The organization to connect to if not already connected.

    .PARAMETER DaysBack
        Optional. Number of days to look back for activity. Default is 30.

    .PARAMETER IncludeWorkItems
        Optional. Include work item activity. Default is true.

    .EXAMPLE
        Get-AzDOTeamActivity -TeamName "MyTeam" -DaysBack 14
        Gets activity for the MyTeam team in the default project for the last 14 days.

    .EXAMPLE
        Get-AzDOTeamActivity -TeamName "MyTeam" -ProjectName "MyProject" -OrgName "MyOrganization"
        Gets all activity for the MyTeam team in the specified org/project.

    .EXAMPLE
        Get-AzDOTeamActivity -TeamName "DevTeam" -DaysBack 7 -IncludeWorkItems $false
        Gets activity for the DevTeam for the last week, excluding work items.

    .NOTES
        This function requires:
        - VSTeam PowerShell module
        - Active connection to Azure DevOps (use Connect-AzDO first)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TeamName,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectName,
        
        [Parameter(Mandatory = $false)]
        [string]$OrgName,
        
        [Parameter(Mandatory = $false)]
        [int]$DaysBack = 30,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeWorkItems = $true
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
        
        $project = if ($ProjectName) { $ProjectName } else { $info.DefaultProject }
        Write-Verbose "Gathering activity for team '$TeamName' in project '$project' for the last $DaysBack days..."
        
        $dateFilter = (Get-Date).AddDays(-$DaysBack)
        
        # Create a results object
        $results = [PSCustomObject]@{
            TeamName  = $TeamName
            Project   = $project
            Period    = "$DaysBack days (since $($dateFilter.ToString('yyyy-MM-dd')))"
            WorkItems = $null
            Summary   = $null
        }
        
        # Get work items
        if ($IncludeWorkItems) {
            Write-Verbose "Fetching work item activity..."
            
            # Work items created
            $createdQuery = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.CreatedDate], [System.CreatedBy] FROM WorkItems " +
            "WHERE [System.TeamProject] = '$project' AND [System.AreaPath] UNDER '$project\\$TeamName' " +
            "AND [System.CreatedDate] >= '$($dateFilter.ToString('yyyy-MM-dd'))' " +
            "ORDER BY [System.CreatedDate] DESC"
                            
            Write-Verbose "Executing created items query..."
            $createdItems = Get-VSTeamWiql -Query $createdQuery -Expand
            
            # Work items updated
            $updatedQuery = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.ChangedDate], [System.ChangedBy] FROM WorkItems " +
            "WHERE [System.TeamProject] = '$project' AND [System.AreaPath] UNDER '$project\\$TeamName' " +
            "AND [System.ChangedDate] >= '$($dateFilter.ToString('yyyy-MM-dd'))' " +
            "AND [System.ChangedDate] <> [System.CreatedDate] " +
            "ORDER BY [System.ChangedDate] DESC"
                            
            Write-Verbose "Executing updated items query..."
            $updatedItems = Get-VSTeamWiql -Query $updatedQuery -Expand
            
            $results.WorkItems = [PSCustomObject]@{
                Created      = $createdItems.workItems | Select-Object id, 
                @{Name = "Title"; Expression = { $_.fields."System.Title" } }, 
                @{Name = "Type"; Expression = { $_.fields."System.WorkItemType" } }, 
                @{Name = "State"; Expression = { $_.fields."System.State" } }, 
                @{Name = "CreatedBy"; Expression = { $_.fields."System.CreatedBy".displayName } }, 
                @{Name = "CreatedDate"; Expression = { $_.fields."System.CreatedDate" } },
                @{Name = "URL"; Expression = { $_.url } }
                Updated      = $updatedItems.workItems | Select-Object id, 
                @{Name = "Title"; Expression = { $_.fields."System.Title" } }, 
                @{Name = "Type"; Expression = { $_.fields."System.WorkItemType" } }, 
                @{Name = "State"; Expression = { $_.fields."System.State" } }, 
                @{Name = "ChangedBy"; Expression = { $_.fields."System.ChangedBy".displayName } }, 
                @{Name = "ChangedDate"; Expression = { $_.fields."System.ChangedDate" } },
                @{Name = "URL"; Expression = { $_.url } }
                CreatedCount = $createdItems.workItems.Count
                UpdatedCount = $updatedItems.workItems.Count
            }
        }
        
        # Create a summary
        $summary = @()
        $summary += "Activity summary for team '$TeamName' in the last $DaysBack days:"
        
        if ($IncludeWorkItems) {
            $summary += "- Work Items Created: $($results.WorkItems.CreatedCount)"
            $summary += "- Work Items Updated: $($results.WorkItems.UpdatedCount)"
        }
        
        $results.Summary = $summary
        
        # Display the summary
        Write-Verbose ($results.Summary -join "`n")
        
        return $results
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
} 
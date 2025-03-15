function Get-AzDOTeamWorkItems {
    <#
    .SYNOPSIS
        Retrieves work items for a specific team in Azure DevOps.

    .DESCRIPTION
        This function queries and returns work items associated with a specified team in Azure DevOps.
        It can filter by work item types, state, and other criteria.
        The function supports different detail levels for output and handles common state variations.

    .PARAMETER TeamName
        The name of the team to get work items for.

    .PARAMETER ProjectName
        Optional. The project name. If not specified, uses the default project.

    .PARAMETER OrgName
        Optional. The organization to connect to if not already connected.

    .PARAMETER WorkItemType
        Optional. Filter by work item type (e.g., "User Story", "Bug", "Task").

    .PARAMETER State
        Optional. Filter by state (e.g., "Active", "Closed", "Resolved").
        Supports common variations:
        - "Active" includes: Active, In Progress, Committed, Development
        - "Closed" includes: Closed, Done, Completed
        - "Resolved" includes: Resolved, Ready for Test

    .PARAMETER MaxCount
        Optional. Maximum number of work items to return. Default is 200.

    .PARAMETER DetailLevel
        Optional. Level of detail to include: "Brief", "Normal", "Full". Default is "Normal".
        - Brief: Shows ID, Title, Type, and State
        - Normal: Adds AssignedTo information
        - Full: Shows all available fields

    .EXAMPLE
        Get-AzDOTeamWorkItems -TeamName "MyTeam" -WorkItemType "User Story" -State "Active"
        Gets active user stories for the MyTeam team in the default project.

    .EXAMPLE
        Get-AzDOTeamWorkItems -TeamName "MyTeam" -ProjectName "MyProject" -OrgName "MyOrganization" -DetailLevel "Full"
        Connects to the specified org/project and gets detailed work items for the MyTeam team.

    .EXAMPLE
        Get-AzDOTeamWorkItems -TeamName "DevTeam" -State "Closed" -MaxCount 50
        Gets the 50 most recently changed closed work items for the DevTeam.

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
        [string]$WorkItemType,
        
        [Parameter(Mandatory = $false)]
        [string]$State,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxCount = 200,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Brief", "Normal", "Full")]
        [string]$DetailLevel = "Normal"
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
        
        # Build the WIQL query
        $wiqlQuery = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.CreatedDate], [System.AssignedTo], [System.IterationPath], [System.Tags] FROM WorkItems WHERE [System.TeamProject] = '$project'"
        
        # Add team area filter
        $wiqlQuery += " AND [System.AreaPath] UNDER '$project\\$TeamName'"
        
        # Add work item type filter if specified
        if ($WorkItemType) {
            $wiqlQuery += " AND [System.WorkItemType] = '$WorkItemType'"
        }
        
        # Add state filter if specified
        if ($State) {
            # Handle common state variations
            $stateConditions = switch ($State.ToLower()) {
                "active" { "'Active', 'In Progress', 'Committed', 'Development'" }
                "closed" { "'Closed', 'Done', 'Completed'" }
                "resolved" { "'Resolved', 'Ready for Test'" }
                default { "'$State'" }
            }
            $wiqlQuery += " AND [System.State] IN ($stateConditions)"
        }
        
        # Add order by clause
        $wiqlQuery += " ORDER BY [System.ChangedDate] DESC"
        
        Write-Verbose "Executing WIQL query: $wiqlQuery"
        
        # Execute the query
        $queryResults = Get-VSTeamWiql -Query $wiqlQuery -Expand -Top $MaxCount -ProjectName $project
        
        if ($queryResults.workItems.Count -eq 0) {
            Write-Warning "No work items found matching the criteria."
            return
        }
        
        # Format the output based on detail level
        $output = switch ($DetailLevel) {
            "Brief" {
                $queryResults.workItems | Select-Object id, 
                @{Name = "Title"; Expression = { $_.fields."System.Title" } }, 
                @{Name = "Type"; Expression = { $_.fields."System.WorkItemType" } }, 
                @{Name = "State"; Expression = { $_.fields."System.State" } }
            }
            "Normal" {
                $queryResults.workItems | Select-Object id, 
                @{Name = "Title"; Expression = { $_.fields."System.Title" } }, 
                @{Name = "Type"; Expression = { $_.fields."System.WorkItemType" } }, 
                @{Name = "State"; Expression = { $_.fields."System.State" } }, 
                @{Name = "AssignedTo"; Expression = {
                        if ($_.fields."System.AssignedTo") {
                            $_.fields."System.AssignedTo".displayName
                        }
                        else {
                            "Unassigned"
                        }
                    }
                },
                @{Name = "URL"; Expression = { $_.url } }
            }
            "Full" {
                $queryResults.workItems | Select-Object *
            }
        }
        
        return $output
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
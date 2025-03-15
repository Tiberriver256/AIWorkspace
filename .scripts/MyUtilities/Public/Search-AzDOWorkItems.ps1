function Search-AzDOWorkItems {
    <#
    .SYNOPSIS
        Searches work items in Azure DevOps using the Azure DevOps Search API.

    .DESCRIPTION
        This function provides powerful work item search capabilities across Azure DevOps projects.
        It supports various filters including work item type, state, and assigned to.

    .PARAMETER SearchText
        The text to search for in work items.

    .PARAMETER ProjectName
        Optional. The project to search in. If not specified, uses the default project.

    .PARAMETER WorkItemTypes
        Optional. Array of work item types to filter by (e.g., "Bug", "User Story", "Task").

    .PARAMETER States
        Optional. Array of work item states to filter by (e.g., "Active", "Closed").

    .PARAMETER AssignedTo
        Optional. Filter by work items assigned to this user.

    .PARAMETER OrderByField
        Optional. Field to sort results by. Default is "System.ChangedDate".

    .PARAMETER SortOrder
        Optional. Sort direction. Valid values: "ASC", "DESC"
        Default: "DESC"

    .PARAMETER MaxResults
        Optional. Maximum number of results to return.
        Default: 10

    .PARAMETER IncludeFacets
        Optional switch. Include faceted search results showing result counts by type.

    .EXAMPLE
        Search-AzDOWorkItems -SearchText "performance issue"
        Searches for work items containing "performance issue"

    .EXAMPLE
        Search-AzDOWorkItems -SearchText "critical" -WorkItemTypes "Bug" -States "Active"
        Searches for active bugs with "critical" in them

    .EXAMPLE
        Search-AzDOWorkItems -SearchText "refactor" -AssignedTo "user@example.com"
        Searches for work items assigned to user@example.com containing "refactor"

    .NOTES
        This function requires:
        - VSTeam PowerShell module
        - Active connection to Azure DevOps (use Connect-AzDO or Invoke-SetupAzDOConnection first)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SearchText,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectName,
        
        [Parameter(Mandatory = $false)]
        [string[]]$WorkItemTypes,
        
        [Parameter(Mandatory = $false)]
        [string[]]$States,
        
        [Parameter(Mandatory = $false)]
        [string]$AssignedTo,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("ASC", "DESC")]
        [string]$SortOrder = "DESC",

        [Parameter(Mandatory = $false)]
        [string]$OrderByField = "System.ChangedDate",

        [Parameter(Mandatory = $false)]
        [int]$MaxResults = 10,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFacets
    )

    $ErrorActionPreference = "Stop"

    try {
        # Get current connection info
        $info = Get-VSTeamInfo
        if (-not $info.Account) {
            Write-Verbose "No active connection, running setup wizard..."
            & "$PSScriptRoot/../Private/Invoke-SetupAzDOConnection.ps1"
            $info = Get-VSTeamInfo
        }

        $project = if ($ProjectName) { $ProjectName } else { $info.DefaultProject }
        if (-not $project) {
            throw "No project specified and no default project set."
        }

        # Construct the search request
        $searchRequest = @{
            searchText = $SearchText
            '$skip' = 0
            '$top' = $MaxResults
            filters = @{
                'System.TeamProject' = @($project)
            }
            '$orderBy' = @(
                @{
                    field = $OrderByField
                    sortOrder = $SortOrder
                }
            )
            includeFacets = [bool]$IncludeFacets
        }

        if ($WorkItemTypes) {
            $searchRequest.filters.'System.WorkItemType' = $WorkItemTypes
        }

        if ($States) {
            $searchRequest.filters.'System.State' = $States
        }

        if ($AssignedTo) {
            $searchRequest.filters.'System.AssignedTo' = @($AssignedTo)
        }

        Write-Verbose "Search request: $($searchRequest | ConvertTo-Json -Depth 10)"

        # Handle authentication
        $auth = Get-AzDOAuthenticationHeader
        Write-Verbose "Using auth header type: $($auth.Header.Authorization.Split(' ')[0])"

        # Construct the request URL
        $orgUrl = $info.Account -replace "https://dev.azure.com/", ""
        $apiVersion = "7.2-preview.1"
        $url = "https://almsearch.dev.azure.com/$orgUrl/_apis/search/workitemsearchresults?api-version=$apiVersion"

        # Make the request with verbose logging
        Write-Verbose "Sending request to $url"
        $response = Invoke-RestMethod -Uri $url -Method Post -Body ($searchRequest | ConvertTo-Json -Depth 10) -Headers $auth.Header

        # Format and return the results
        if ($response.count -eq 0) {
            Write-Host "No results found." -ForegroundColor Yellow
            return
        }

        Write-Host "Found $($response.count) results:" -ForegroundColor Green

        $results = $response.results | Select-Object @{
            Name = "ID"
            Expression = { $_.fields."system.id" }
        }, @{
            Name = "Project"
            Expression = { $_.project.name }
        }, @{
            Name = "Title"
            Expression = { $_.fields."system.title" }
        }, @{
            Name = "Type"
            Expression = { $_.fields."system.workitemtype" }
        }, @{
            Name = "State"
            Expression = { $_.fields."system.state" }
        }, @{
            Name = "AssignedTo"
            Expression = { $_.fields."system.assignedto" }
        }, @{
            Name = "Tags"
            Expression = { $_.fields."system.tags" }
        }, @{
            Name = "Changed"
            Expression = { $_.fields."system.changeddate" }
        }, @{
            Name = "Highlights"
            Expression = { 
                $_.hits | ForEach-Object {
                    "$($_.fieldReferenceName): $($_.highlights -join ', ')"
                } | Out-String
            }
        }, @{
            Name = "URL"
            Expression = { $_.url }
        }

        # Show results
        $results | Format-List

        # Show facets if requested
        if ($IncludeFacets -and $response.facets) {
            Write-Host "`nSearch Facets:" -ForegroundColor Cyan
            
            foreach ($facetKey in $response.facets.PSObject.Properties.Name) {
                Write-Host "`n${facetKey}:" -ForegroundColor Yellow
                $response.facets.$facetKey | 
                    Where-Object { $_.resultCount -gt 0 } |
                    Select-Object @{
                        Name = "Name"
                        Expression = { $_.name }
                    }, @{
                        Name = "Count"
                        Expression = { $_.resultCount }
                    } | 
                    Format-Table -AutoSize
            }
        }

        return $results
    }
    catch {
        Write-Error "Failed to search work items: $_"
        Write-Error "Request: $($searchRequest | ConvertTo-Json)"
    }
} 
function Search-AzDOCode {
    <#
    .SYNOPSIS
        Searches code across Azure DevOps repositories using the Azure DevOps Search API.
    .DESCRIPTION
        This function provides powerful code search capabilities across Azure DevOps repositories.
        It supports various search patterns and filters to help you find exactly what you're looking for.
        Search Syntax Examples:
        - Basic text search: "QueueJobsNow"
        - Search in specific project: "QueueJobsNow proj:Fabrikam"
        - Search in specific repo: "QueueJobsNow repo:Contoso"
        - Search in specific path: "QueueJobsNow path:VisualStudio/Services/Framework"
        - Search specific file types: "QueueJobsNow ext:cs"
        - Search specific files: "QueueJobsNow file:queueRegister*"
        Code Element Search:
        - Find class definitions: "class:ILogger"
        - Find interfaces: "interface:ILogger"
        - Find methods: "method:ProcessQueue"
        - Find properties: "prop:Name"
        - Find comments: "comment:TODO"
        - Find string literals: "strlit:error occurred"
        - Find namespaces: "namespace:Microsoft.Azure"
        - Find types: "type:Logger"
        - Find fields: "field:_logger"
        - Find declarations: "decl:ILogger"
        - Find definitions: "def:ProcessQueue"
        - Find references: "ref:ILogger"
        Advanced Search Patterns:
        - Wildcards: Use * for multiple characters, ? for single character
        - Path wildcards: "path:**/Tests/**/*.cs" finds all .cs files under any Tests folder
        - Multiple terms: "interface:ILogger class:ConsoleLogger" finds both patterns
        - Exact matches: Use quotes "exact phrase"
        - Comments search: "comment:TODO" finds all TODO comments
        - Combined search: "method:Process* comment:TODO" finds methods starting with Process that have TODO comments
    .PARAMETER SearchText
        The text to search for. Can include special search syntax (see Description for examples).
    .PARAMETER ProjectName
        Optional. The project to search in. If not specified, uses the default project.
    .PARAMETER Repositories
        Optional. Array of repository names to search in.
    .PARAMETER Path
        Optional. Path filter to limit search to specific folders.
        Note: Path filter can only be used when searching a single repository.
    .PARAMETER Branch
        Optional. The branch to search in. If not specified, searches the default branch.
    .PARAMETER OrderByField
        Optional. Field to sort results by. Valid values: "filename", "path", "repository"
        Default: "filename"
    .PARAMETER SortOrder
        Optional. Sort direction. Valid values: "ASC", "DESC"
        Default: "DESC"
    .PARAMETER MaxResults
        Optional. Maximum number of results to return.
        Default: 10
    .PARAMETER IncludeFacets
        Optional switch. Include faceted search results showing result counts by type.
    .EXAMPLE
        Search-AzDOCode -SearchText "TODO"
        Searches for "TODO" in all code, returning up to 10 results
    .EXAMPLE
        Search-AzDOCode -SearchText "interface:ILogger" -MaxResults 50
        Searches for interface definitions named ILogger, returning up to 50 results
    .EXAMPLE
        Search-AzDOCode -SearchText "method:ProcessQueue path:Services/"
        Searches for methods named ProcessQueue in paths containing Services/
    .EXAMPLE
        Search-AzDOCode -SearchText "comment:TODO" -Repositories "MyRepo" -Path "src/main"
        Searches for TODO comments in the MyRepo repository under src/main
    .EXAMPLE
        Search-AzDOCode -SearchText "error ext:cs" -IncludeFacets
        Searches for "error" in C# files and includes faceted results
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
        [string[]]$Repositories,
        
        [Parameter(Mandatory = $false)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$Branch,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("class", "def", "comment", "namespace", "enum", "interface")]
        [string[]]$CodeElements,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("filename", "path", "repository")]
        [string]$OrderByField = "filename",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("ASC", "DESC")]
        [string]$SortOrder = "DESC",
        
        [Parameter(Mandatory = $false)]
        [int]$MaxResults = 10,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeFacets
    )

    $ErrorActionPreference = "Stop"
    try {
        # Get current connection info and refresh if needed
        Write-Verbose "Getting current VSTeam connection..."
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
                Project = @($project)
            }
            '$orderBy' = @(
                @{
                    field = $OrderByField
                    sortOrder = $SortOrder
                }
            )
            includeFacets = [bool]$IncludeFacets
        }

        # Get repositories if Path is specified but no repositories are
        if ($Path) {
            if (-not $Repositories -or $Repositories.Count -gt 1) {
                Write-Warning "Path filter can only be used with a single repository. Ignoring Path filter."
                $Path = $null
            }
        }

        if ($Repositories) {
            $searchRequest.filters.Repository = $Repositories
            
            # Only add Path filter if we have a single repository
            if ($Path -and $Repositories.Count -eq 1) {
                $searchRequest.filters.Path = @($Path)
            }
        }

        # Only add Branch filter if explicitly provided
        if ($Branch) {
            $searchRequest.filters.Branch = @($Branch)
        }

        if ($CodeElements) {
            $searchRequest.filters.CodeElement = $CodeElements
        }

        Write-Verbose "Search request: $($searchRequest | ConvertTo-Json -Depth 10)"

        # Handle authentication
        $auth = Get-AzDOAuthenticationHeader
        Write-Verbose "Using auth header type: $($auth.Header.Authorization.Split(' ')[0])"

        # Construct the request URL
        $orgUrl = $info.Account -replace "https://dev.azure.com/", ""
        $apiVersion = "7.2-preview.1"
        $url = "https://almsearch.dev.azure.com/$orgUrl/_apis/search/codesearchresults?api-version=$apiVersion"

        # Make the request with verbose logging
        Write-Verbose "Sending request to $url"
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -Body ($searchRequest | ConvertTo-Json -Depth 10) -Headers $auth.Header -ErrorAction Stop
            
            if ($response.GetType().Name -eq "String") {
                Write-Verbose "Raw response: $response"
                throw "Received HTML response instead of JSON. This usually indicates an authentication or API endpoint issue."
            }
        }
        catch {
            Write-Verbose "Raw error: $_"
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode
                Write-Verbose "Status code: $statusCode"
                
                try {
                    $rawResponse = $_.ErrorDetails.Message
                    Write-Verbose "Error details: $rawResponse"
                }
                catch {
                    Write-Verbose "Could not get error details"
                }
            }
            throw
        }

        # Format and return the results
        if ($response.count -eq 0) {
            Write-Host "No results found." -ForegroundColor Yellow
            return @()
        }

        Write-Host "Found $($response.count) results:" -ForegroundColor Green

        # Format results
        $results = $response.results | ForEach-Object {
            $result = [PSCustomObject]@{
                Repository = $_.project.name
                Path = $_.path
                FileName = $_.fileName
                Branch = $_.branch
                Matches = $_.matches
                URL = $_.url
                Highlights = ($_.hits | ForEach-Object {
                    "$($_.fieldReferenceName): $($_.highlights -join ', ')"
                }) -join "`n"
            }

            # Try to get file content
            try {
                Write-Verbose "Fetching content for $($_.path)"
                $content = Get-AzDORepositoryItem -RepositoryId $_.repository.name -Path $_.path -IncludeContent -Format "json"
                if ($content.content) {
                    Add-Member -InputObject $result -MemberType NoteProperty -Name "Content" -Value $content.content
                }
                elseif ($content) {
                    # Some files might return content directly in the response
                    Add-Member -InputObject $result -MemberType NoteProperty -Name "Content" -Value $content
                }
            }
            catch {
                Write-Verbose "Failed to fetch content for $($_.path): $_"
                Write-Verbose "Response type was: $($content.GetType().Name)"
            }

            $result
        }

        $facets = @()

        # Show facets if requested
        if ($IncludeFacets -and $response.facets) {
            Write-Host "`nSearch Facets:" -ForegroundColor Cyan
            
            foreach ($facetKey in $response.facets.PSObject.Properties.Name) {
                Write-Host "`n${facetKey}:" -ForegroundColor Yellow
                $facets = $response.facets.$facetKey | 
                    Where-Object { $_.resultCount -gt 0 } |
                    Select-Object @{
                        Name = "Name"
                        Expression = { $_.name }
                    }, @{
                        Name = "Count"
                        Expression = { $_.resultCount }
                    }
            }
            return @{ Results = $results; Facets = $facets }
        }

        return $results
    }
    catch {
        Write-Error "Failed to search code: $_"
        Write-Error "Request: $($searchRequest | ConvertTo-Json)"
    }
}
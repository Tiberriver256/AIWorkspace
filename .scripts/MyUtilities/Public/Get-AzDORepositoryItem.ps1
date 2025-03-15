function Get-AzDORepositoryItem {
    <#
    .SYNOPSIS
        Gets an item (file or folder) from an Azure DevOps Git repository.
    .DESCRIPTION
        This function retrieves items from Azure DevOps Git repositories using the Git Items API.
        It can fetch both file content and metadata, and supports various options like downloading,
        specifying versions, and recursion levels.
    .PARAMETER ProjectName
        The name of the Azure DevOps project. If not specified, uses the default project.
    .PARAMETER RepositoryId
        The name or ID of the repository.
    .PARAMETER Path
        The path to the item in the repository.
    .PARAMETER ScopePath
        Optional. The path scope to limit search within. Default is null.
    .PARAMETER RecursionLevel
        Optional. The recursion level for retrieving items.
        Valid values: "none", "oneLevel", "full", "oneLevelPlusNestedEmptyFolders"
        Default: "none"
    .PARAMETER IncludeContent
        Optional. Switch to include item content in the response.
    .PARAMETER IncludeContentMetadata
        Optional. Switch to include content metadata.
    .PARAMETER LatestProcessedChange
        Optional. Switch to include the latest changes.
    .PARAMETER Download
        Optional. Switch to download the response as a file.
    .PARAMETER Version
        Optional. Version string identifier (name of tag/branch, SHA1 of commit)
    .PARAMETER VersionType
        Optional. Version type (branch, tag, or commit). Determines how Version is interpreted.
        Valid values: "branch", "tag", "commit"
    .PARAMETER VersionOptions
        Optional. Additional version modifiers.
        Valid values: "none", "previousChange", "firstParent"
    .PARAMETER Format
        Optional. Override the response format.
        Valid values: "json", "zip", "text", "octetStream"
    .PARAMETER ResolveLfs
        Optional. Switch to resolve Git LFS pointer files.
    .PARAMETER Sanitize
        Optional. Switch to sanitize SVG files and return as images.
    .EXAMPLE
        Get-AzDORepositoryItem -RepositoryId "MyRepo" -Path "/src/file.cs"
        Gets metadata for file.cs in the MyRepo repository
    .EXAMPLE
        Get-AzDORepositoryItem -RepositoryId "MyRepo" -Path "/src" -RecursionLevel "oneLevel"
        Lists all items one level deep in the /src folder
    .EXAMPLE
        Get-AzDORepositoryItem -RepositoryId "MyRepo" -Path "/src/file.cs" -IncludeContent -Download
        Downloads file.cs and includes its content
    .EXAMPLE
        Get-AzDORepositoryItem -RepositoryId "MyRepo" -Path "/src/file.cs" -Version "main" -VersionType "branch"
        Gets file.cs from the main branch
    .NOTES
        This function requires:
        - VSTeam PowerShell module
        - Active connection to Azure DevOps (use Connect-AzDO or Invoke-SetupAzDOConnection first)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ProjectName,
        
        [Parameter(Mandatory = $true)]
        [string]$RepositoryId,
        
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$ScopePath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("none", "oneLevel", "full", "oneLevelPlusNestedEmptyFolders")]
        [string]$RecursionLevel = "none",
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeContent,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeContentMetadata,
        
        [Parameter(Mandatory = $false)]
        [switch]$LatestProcessedChange,
        
        [Parameter(Mandatory = $false)]
        [switch]$Download,
        
        [Parameter(Mandatory = $false)]
        [string]$Version,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("branch", "tag", "commit")]
        [string]$VersionType,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("none", "previousChange", "firstParent")]
        [string]$VersionOptions = "none",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("json", "zip", "text", "octetStream")]
        [string]$Format,
        
        [Parameter(Mandatory = $false)]
        [switch]$ResolveLfs,
        
        [Parameter(Mandatory = $false)]
        [switch]$Sanitize
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

        # Build query parameters
        $queryParams = @{
            "api-version" = "7.2-preview.1"
            "path" = $Path
        }

        if ($ScopePath) { $queryParams["scopePath"] = $ScopePath }
        if ($RecursionLevel -ne "none") { $queryParams["recursionLevel"] = $RecursionLevel }
        if ($IncludeContent) { $queryParams["includeContent"] = "true" }
        if ($IncludeContentMetadata) { $queryParams["includeContentMetadata"] = "true" }
        if ($LatestProcessedChange) { $queryParams["latestProcessedChange"] = "true" }
        if ($Download) { $queryParams["download"] = "true" }
        if ($Format) { $queryParams['$format'] = $Format }
        if ($ResolveLfs) { $queryParams["resolveLfs"] = "true" }
        if ($Sanitize) { $queryParams["sanitize"] = "true" }
        
        # Add version parameters if specified
        if ($Version) {
            $queryParams["versionDescriptor.version"] = $Version
            if ($VersionType) {
                $queryParams["versionDescriptor.versionType"] = $VersionType
            }
            $queryParams["versionDescriptor.versionOptions"] = $VersionOptions
        }

        # Build query string
        $queryString = ($queryParams.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
        }) -join "&"

        # Construct the request URL
        $orgUrl = $info.Account -replace "https://dev.azure.com/", ""
        $url = "https://dev.azure.com/$orgUrl/$project/_apis/git/repositories/$RepositoryId/items?$queryString"

        # Get authentication header
        $auth = Get-AzDOAuthenticationHeader
        Write-Verbose "Using auth header type: $($auth.Header.Authorization.Split(' ')[0])"

        # Make the request
        Write-Verbose "Sending request to $url"
        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $auth.Header -ErrorAction Stop
            
            if ($response.GetType().Name -eq "String") {
                Write-Verbose "Raw response: $response"
                throw "Received HTML response instead of JSON. This usually indicates an authentication or API endpoint issue."
            }

            # Return the response
            return $response
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
    }
    catch {
        Write-Error "Failed to get repository item: $_"
    }
} 
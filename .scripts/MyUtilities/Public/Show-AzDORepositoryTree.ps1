function Show-AzDORepositoryTree {
    <#
    .SYNOPSIS
        Displays a tree view of files and directories in Azure DevOps repositories.

    .DESCRIPTION
        This function displays a hierarchical tree view of files and directories in Azure DevOps repositories,
        similar to the Unix 'tree' command but for Azure DevOps content. It leverages the Azure DevOps
        REST APIs to retrieve repository content and displays it in a tree-like format.

    .PARAMETER Organization
        The name of the Azure DevOps organization. If not specified, uses the currently connected organization.

    .PARAMETER Project
        The name of the Azure DevOps project. If not specified, uses the current default project if set.

    .PARAMETER Repository
        Optional. The name of one or more specific repositories to show. If not specified, all repositories in the project will be shown.

    .PARAMETER RepositoryPattern
        Optional. A pattern to filter repositories by name using wildcards (e.g., "My*Repos"). This is applied after retrieving the list of repositories.

    .PARAMETER Branch
        Optional. The name of the branch to inspect. If not specified, uses the default branch.

    .PARAMETER Depth
        Optional. The maximum depth of the tree to display. Default is unlimited.

    .PARAMETER Pattern
        Optional. Filter files/folders by name or pattern. Uses PowerShell wildcards.

    .PARAMETER ExportPath
        Optional. Path to export the tree output to a text file.

    .PARAMETER PlainText
        Optional. Forces plain text output without color or special Unicode characters. Useful when piping output to clipboard or files.

    .EXAMPLE
        Show-AzDORepositoryTree -Organization "MyOrg" -Project "MyProject"
        Shows the tree structure of all repositories in the specified project.

    .EXAMPLE
        Show-AzDORepositoryTree -Repository "MyRepo" -Branch "feature/new-feature"
        Shows the tree structure of the specified repository and branch.

    .EXAMPLE
        Show-AzDORepositoryTree -Repository "MyRepo1","MyRepo2" -Depth 2
        Shows the tree structure of multiple repositories with a maximum depth of 2 levels.

    .EXAMPLE
        Show-AzDORepositoryTree -RepositoryPattern "API*" -Depth 2
        Shows the tree structure of all repositories with names starting with "API".

    .EXAMPLE
        Show-AzDORepositoryTree -Depth 3 -Pattern "*.cs"
        Shows the tree structure with a maximum depth of 3 levels, including only .cs files.

    .EXAMPLE
        Show-AzDORepositoryTree -Repository "MyRepo" -ExportPath "C:\temp\repo-tree.txt"
        Shows the tree structure and exports it to a file.

    .EXAMPLE
        Show-AzDORepositoryTree -Repository "MyRepo" -PlainText | clip
        Shows the tree structure with plain ASCII characters and no color, making it suitable for copying to clipboard.

    .NOTES
        This function requires an active connection to Azure DevOps via Connect-AzDO.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Organization,
        
        [Parameter()]
        [string]$Project,
        
        [Parameter()]
        [string[]]$Repository,
        
        [Parameter()]
        [string]$RepositoryPattern,
        
        [Parameter()]
        [string]$Branch,
        
        [Parameter()]
        [int]$Depth = 0,
        
        [Parameter()]
        [string]$Pattern,
        
        [Parameter()]
        [string]$ExportPath,
        
        [Parameter()]
        [switch]$PlainText
    )

    # Initialize counters for files and directories
    $script:fileCount = 0
    $script:dirCount = 0
    $script:repoCount = 0
    
    # Check if output is being piped or redirected, or user has explicitly requested plain text
    # This checks several conditions that might indicate we're not writing directly to console
    $pipelinePosition = $MyInvocation.PipelinePosition
    $pipelineLength = $MyInvocation.PipelineLength
    $script:isOutputPiped = $PlainText -or 
                           ($pipelinePosition -lt $pipelineLength) -or 
                           (-not [Environment]::UserInteractive) -or
                           ([console]::IsOutputRedirected) -or
                           ($null -eq $Host.UI.RawUI) -or
                           (-not $Host.UI.SupportsVirtualTerminal)
    
    Write-Verbose "Is output piped: $script:isOutputPiped"
    Write-Verbose "Pipeline position: $pipelinePosition of $pipelineLength"
    Write-Verbose "Interactive: $([Environment]::UserInteractive)"
    Write-Verbose "Output redirected: $([console]::IsOutputRedirected)"
    Write-Verbose "Has RawUI: $($null -ne $Host.UI.RawUI)"
    Write-Verbose "Supports VT: $($Host.UI.SupportsVirtualTerminal)"
    
    # Set tree drawing characters based on whether we're piping or not
    if ($script:isOutputPiped) {
        $script:branchSymbol = "|-- "  # Simple ASCII for piped output
    }
    else {
        $script:branchSymbol = "├── "  # Unicode for console display
    }
    
    # OutputMode allows capturing output for export
    if ($ExportPath) {
        $OutputMode = "Capture"
        $Output = [System.Collections.ArrayList]::new()
    }
    else {
        $OutputMode = "Display"
    }

    # Function to output text based on mode
    function Write-TreeOutput {
        param(
            [string]$Text,
            [string]$ForegroundColor = "White"
        )
        
        if ($OutputMode -eq "Display") {
            if ($script:isOutputPiped) {
                Write-Output $Text
            }
            else {
                Write-ColorOutput -ForegroundColor $ForegroundColor $Text
            }
        }
        else {
            [void]$Output.Add($Text)
        }
    }

    # Custom URL Encode function that uses %20 instead of + for spaces
    function Encode-Url {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Value
        )
        
        # First use standard URL encoding
        $encoded = [System.Net.WebUtility]::UrlEncode($Value)
        
        # Then replace + with %20
        $encoded = $encoded.Replace("+", "%20")
        
        return $encoded
    }

    # Get the organization and project
    if (-not $Organization) {
        try {
            $vsTeamAccount = Get-VSTeamInfo
            $Organization = $vsTeamAccount.Account
            
            # Clean up the organization name if it contains a URL
            if ($Organization -match "https://dev.azure.com/(.+)") {
                $Organization = $matches[1]
            }
            
            Write-Verbose "Using organization from VSTeam: $Organization"
        }
        catch {
            throw "No organization specified and no active connection found. Please use Connect-AzDO first or specify -Organization."
        }
    }
    
    if (-not $Project) {
        try {
            $Project = (Get-VSTeamInfo).DefaultProject
            if (-not $Project) {
                throw "No default project set"
            }
            Write-Verbose "Using default project from VSTeam: $Project"
        }
        catch {
            throw "No project specified and no default project set. Please use Connect-AzDO -ProjectName or specify -Project."
        }
    }

    # Get authentication header
    try {
        $auth = Get-AzDOAuthenticationHeader
    }
    catch {
        throw "Failed to get authentication: $_"
    }

    # Handle spaces in project name with proper %20 encoding
    $encodedProject = Encode-Url -Value $Project
    
    # Base URL for Azure DevOps API
    $baseUrl = "https://dev.azure.com/$Organization/$encodedProject/_apis"
    Write-Verbose "Base API URL: $baseUrl"

    # Get repositories in the project
    if ((-not $Repository -or $Repository.Count -eq 0) -or $RepositoryPattern) {
        # Get all repositories in the project first
        $reposUrl = "$baseUrl/git/repositories?api-version=7.1-preview.1"
        Write-Verbose "Retrieving all repositories with URL: $reposUrl"
        
        try {
            $response = Invoke-RestMethod -Uri $reposUrl -Headers $auth.Header -Method Get
            $allRepositories = $response.value
            
            if ($allRepositories.Count -eq 0) {
                Write-TreeOutput "No repositories found in project $Project" -ForegroundColor Yellow
                return
            }
            
            Write-Verbose "Found $($allRepositories.Count) repositories in total"
            
            # Apply the repository pattern filter if specified
            if ($RepositoryPattern) {
                Write-Verbose "Filtering repositories by pattern: $RepositoryPattern"
                $repositories = $allRepositories | Where-Object { $_.name -like $RepositoryPattern }
                Write-Verbose "After pattern filtering, $($repositories.Count) repositories remain"
                
                if ($repositories.Count -eq 0) {
                    Write-TreeOutput "No repositories matched the pattern '$RepositoryPattern'" -ForegroundColor Yellow
                    return
                }
            }
            # Apply the specific repository filter if specified
            elseif ($Repository -and $Repository.Count -gt 0) {
                $repositories = @()
                foreach ($repoName in $Repository) {
                    $matchingRepo = $allRepositories | Where-Object { $_.name -eq $repoName }
                    if ($matchingRepo) {
                        $repositories += $matchingRepo
                        Write-Verbose "Found repository: $repoName"
                    }
                    else {
                        Write-Warning "Repository '$repoName' not found or not accessible"
                    }
                }
                
                if ($repositories.Count -eq 0) {
                    Write-TreeOutput "No valid repositories were found for the specified names" -ForegroundColor Yellow
                    return
                }
            }
            else {
                # Use all repositories
                $repositories = $allRepositories
            }
        }
        catch {
            Write-Error "Failed to get repositories: $_"
            Write-Error "Request URL was: $reposUrl"
            throw "Failed to get repositories: $_"
        }
    }
    else {
        # This case is when only specific repositories are requested without pattern matching
        # We'll attempt to get them directly by name
        $repositories = @()
        
        foreach ($repoName in $Repository) {
            $encodedRepo = Encode-Url -Value $repoName
            $repoUrl = "$baseUrl/git/repositories/$encodedRepo`?api-version=7.1-preview.1"
            Write-Verbose "Retrieving repository '$repoName' with URL: $repoUrl"
            
            try {
                $repo = Invoke-RestMethod -Uri $repoUrl -Headers $auth.Header -Method Get
                $repositories += $repo
                Write-Verbose "Found repository: $($repo.name)"
            }
            catch {
                Write-Error "Failed to get repository '$repoName': $_"
                Write-Error "Request URL was: $repoUrl"
                # Continue to the next repository instead of stopping
                Write-Warning "Repository '$repoName' not found or not accessible"
            }
        }
        
        if ($repositories.Count -eq 0) {
            Write-TreeOutput "No valid repositories were found for the specified names" -ForegroundColor Yellow
            return
        }
    }

    $script:repoCount = $repositories.Count

    Write-TreeOutput "Project: $Project" -ForegroundColor Cyan
    
    # Process each repository
    foreach ($repo in $repositories) {
        Write-TreeOutput "`n$($repo.name)/" -ForegroundColor Blue
        
        # Get the default branch if not specified
        $branchRef = $Branch
        if (-not $branchRef) {
            if ($repo.defaultBranch) {
                # Get the branch name without the refs/heads/ prefix
                $branchRef = $repo.defaultBranch -replace "refs/heads/", ""
                Write-Verbose "Using default branch: $branchRef"
            }
            else {
                Write-TreeOutput "    No default branch found, using 'main'" -ForegroundColor Yellow
                $branchRef = "main"
            }
        }
        
        # Properly encode branch name for URL with %20
        $encodedBranch = Encode-Url -Value $branchRef
        
        # Determine which API approach to use based on depth
        if ($Depth -eq 0) {
            # For unlimited depth, use 'Full' recursion to get all items in one call
            # This is much faster than making separate API calls for each folder
            $recursionLevel = "Full"
            Write-Verbose "Using Full recursion to retrieve all items at once"
        }
        else {
            # For limited depth, we'll still use the level-by-level approach
            $recursionLevel = "OneLevel"
        }
        
        # Get the items in the repository
        $itemsUrl = "$baseUrl/git/repositories/$($repo.id)/items?recursionLevel=$recursionLevel&versionDescriptor.version=$encodedBranch&versionDescriptor.versionType=branch&api-version=7.1-preview.1"
        Write-Verbose "Getting repository items with URL: $itemsUrl"
        
        try {
            $response = Invoke-RestMethod -Uri $itemsUrl -Headers $auth.Header -Method Get
            
            # The root repository object itself comes as the first item, skip it
            $items = $response.value | Where-Object { $_.gitObjectType -ne "bad" -and $_.path -ne "/" }
            
            Write-Verbose "Found $($items.Count) items in the repository"
            
            if ($items.Count -eq 0) {
                Write-TreeOutput "    (Empty repository)" -ForegroundColor Yellow
                continue
            }
            
            if ($recursionLevel -eq "Full") {
                # For Full recursion, we build the tree structure from the flat list of items
                Show-AzDORepositoryTreeFromFlatList -Items $items -Pattern $Pattern -Depth $Depth
            }
            else {
                # For limited depth, use the original approach of fetching level by level
                $rootItems = $items
                Show-AzDORepositoryItems -Items $rootItems -RepoId $repo.id -BranchRef $branchRef -BaseUrl $baseUrl -Auth $auth -Indent "    " -Level 1 -MaxDepth $Depth -Pattern $Pattern
            }
        }
        catch {
            Write-TreeOutput "    Failed to get repository items: $_" -ForegroundColor Red
        }
    }

    # Show summary
    $summary = "`n$script:repoCount repositories, $script:dirCount directories, $script:fileCount files"
    Write-TreeOutput $summary -ForegroundColor Cyan

    # Export to file if requested
    if ($ExportPath) {
        try {
            $Output | Out-File -FilePath $ExportPath -Encoding utf8
            Write-Host "Tree output exported to $ExportPath" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to export tree output: $_"
        }
    }
}

function Show-AzDORepositoryTreeFromFlatList {
    <#
    .SYNOPSIS
        Helper function to display a tree from a flat list of items
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Items,
        
        [Parameter()]
        [string]$Pattern,
        
        [Parameter()]
        [int]$Depth = 0
    )
    
    # Build a hashtable to represent the tree structure
    $treeStructure = @{}
    
    # Sort items by path to ensure parent directories come before their children
    $sortedItems = $Items | Sort-Object path
    
    foreach ($item in $sortedItems) {
        # Skip the root item
        if ($item.path -eq "/") {
            continue
        }
        
        # Remove leading slash if present
        $path = $item.path
        if ($path.StartsWith("/")) {
            $path = $path.Substring(1)
        }
        
        # Split path into segments
        $segments = $path -split '/'
        $level = $segments.Count - 1
        
        # Skip items beyond the depth limit if a depth is specified
        if ($Depth -gt 0 -and $level -ge $Depth) {
            continue
        }
        
        # Apply pattern filter if specified (for files only)
        $name = $segments[-1]
        if ($Pattern -and -not $item.isFolder -and ($name -notlike $Pattern)) {
            continue
        }
        
        # Calculate the full path for this item
        $currentPath = ""
        $currentNode = $treeStructure
        
        # Create or navigate to parent nodes
        for ($i = 0; $i -lt $segments.Count - 1; $i++) {
            $segment = $segments[$i]
            $currentPath = if ($currentPath) { "$currentPath/$segment" } else { $segment }
            
            if (-not $currentNode.ContainsKey($segment)) {
                $currentNode[$segment] = @{
                    "isFolder" = $true
                    "children" = @{}
                    "path"     = $currentPath
                }
                # Count this directory
                $script:dirCount++
            }
            
            $currentNode = $currentNode[$segment].children
        }
        
        # Add the current item to its parent node
        $finalSegment = $segments[-1]
        
        if (-not $currentNode.ContainsKey($finalSegment)) {
            $itemPath = if ($currentPath) { "$currentPath/$finalSegment" } else { $finalSegment }
            
            $currentNode[$finalSegment] = @{
                "isFolder" = $item.isFolder
                "children" = @{}
                "path"     = $itemPath
            }
            
            # Update counters
            if ($item.isFolder) {
                $script:dirCount++
            }
            else {
                $script:fileCount++
            }
        }
    }
    
    # Render the tree
    $rootIndent = "    "
    Show-TreeNode -Node $treeStructure -Indent $rootIndent
}

function Show-TreeNode {
    <#
    .SYNOPSIS
        Helper function to recursively display a tree node
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Node,
        
        [Parameter(Mandatory = $true)]
        [string]$Indent
    )
    
    # Get all keys sorted (directories first, then files alphabetically)
    $sortedKeys = $Node.Keys | Sort-Object { 
        if ($Node[$_].isFolder) { 0 } else { 1 } 
    }, { $_ }
    
    foreach ($key in $sortedKeys) {
        $item = $Node[$key]
        $branchSymbol = $script:branchSymbol
        
        # Set color based on item type
        if ($item.isFolder) {
            $foregroundColor = "Blue"
            $displayName = "$key/"
        }
        else {
            $foregroundColor = "White"
            $displayName = $key
        }
        
        # Output the item
        $outputText = "$Indent$branchSymbol$displayName"
        if ($OutputMode -eq "Display") {
            if ($script:isOutputPiped) {
                Write-Output $outputText
            }
            else {
                Write-ColorOutput -ForegroundColor $foregroundColor $outputText
            }
        }
        else {
            [void]$Output.Add($outputText)
        }
        
        # Recursively process children if this is a directory
        if ($item.isFolder -and $item.children.Count -gt 0) {
            # Use appropriate indentation characters for piped vs. console output
            $indentChar = if ($script:isOutputPiped) { "    " } else { "    " }
            Show-TreeNode -Node $item.children -Indent "$indentChar$Indent"
        }
    }
}

function Show-AzDORepositoryItems {
    <#
    .SYNOPSIS
        Helper function to display repository items in a tree format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Items,
        
        [Parameter(Mandatory = $true)]
        [string]$RepoId,
        
        [Parameter(Mandatory = $true)]
        [string]$BranchRef,
        
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        
        [Parameter(Mandatory = $true)]
        [object]$Auth,
        
        [Parameter(Mandatory = $true)]
        [string]$Indent,
        
        [Parameter(Mandatory = $true)]
        [int]$Level,
        
        [Parameter()]
        [int]$MaxDepth = 0,
        
        [Parameter()]
        [string]$Pattern
    )

    # Sort items (directories first, then files)
    $sortedItems = $Items | Sort-Object { 
        if ($_.isFolder) { 0 } else { 1 } 
    }, { $_.path }

    foreach ($item in $sortedItems) {
        # Apply pattern filter if specified
        $itemName = Split-Path -Path $item.path -Leaf
        if ($Pattern -and (-not $item.isFolder) -and ($itemName -notlike $Pattern)) {
            continue
        }
        
        # Create the branch symbol
        $branchSymbol = $script:branchSymbol
        
        # Prepare the display name
        $displayName = $itemName
        
        # Set color based on item type
        if ($item.isFolder) {
            # Update directory count
            $script:dirCount++
            $foregroundColor = "Blue"
            $displayName += "/"
        }
        else {
            # Update file count
            $script:fileCount++
            $foregroundColor = "White"
        }
        
        # Output the item
        $outputText = "$Indent$branchSymbol$displayName"
        if ($OutputMode -eq "Display") {
            if ($script:isOutputPiped) {
                Write-Output $outputText
            }
            else {
                Write-ColorOutput -ForegroundColor $foregroundColor $outputText
            }
        }
        else {
            [void]$Output.Add($outputText)
        }
        
        # If it's a folder and we haven't reached max depth, get its contents
        if ($item.isFolder -and ($MaxDepth -eq 0 -or $Level -lt $MaxDepth)) {
            # Get items in this folder
            $folderPath = $item.path
            if ($folderPath.StartsWith("/")) {
                $folderPath = $folderPath.Substring(1)
            }
            
            # Properly encode folder path and branch name for URL using %20 instead of +
            $encodedFolderPath = Encode-Url -Value $folderPath
            $encodedBranch = Encode-Url -Value $BranchRef
            
            # Update API version to match the documentation
            $folderUrl = "$BaseUrl/git/repositories/$RepoId/items?recursionLevel=OneLevel&scopePath=$encodedFolderPath&versionDescriptor.version=$encodedBranch&versionDescriptor.versionType=branch&api-version=7.1-preview.1"
            
            try {
                $response = Invoke-RestMethod -Uri $folderUrl -Headers $Auth.Header -Method Get
                $folderItems = $response.value | Where-Object { $_.gitObjectType -ne "bad" -and $_.path -ne $item.path }
                
                if ($folderItems.Count -gt 0) {
                    # Recursively display the items in this folder
                    Show-AzDORepositoryItems -Items $folderItems -RepoId $RepoId -BranchRef $BranchRef -BaseUrl $BaseUrl -Auth $Auth -Indent "    $Indent" -Level ($Level + 1) -MaxDepth $MaxDepth -Pattern $Pattern
                }
            }
            catch {
                $errorText = "    $Indent  Failed to get folder items: $_"
                if ($OutputMode -eq "Display") {
                    if ($script:isOutputPiped) {
                        Write-Output $errorText
                    }
                    else {
                        Write-ColorOutput -ForegroundColor "Red" $errorText
                    }
                }
                else {
                    [void]$Output.Add($errorText)
                }
            }
        }
    }
}
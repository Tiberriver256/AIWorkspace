function Show-Tree {
    <#
    .SYNOPSIS
        Displays a tree view of files and directories in a specified path.

    .DESCRIPTION
        This function displays a hierarchical tree view of files and directories, similar to the Unix 'tree' command.
        It supports excluding patterns and respecting .gitignore rules.
        The output includes proper indentation and branch symbols for visual hierarchy.
        At the end, it provides a summary of the total number of files and directories.

    .PARAMETER Path
        The path to display the tree for. Defaults to the current directory.

    .PARAMETER ExcludePattern
        Array of patterns to exclude from the tree. Uses PowerShell wildcards.
        Default excludes the .git directory.

    .PARAMETER UseGitIgnore
        If set, the function will respect .gitignore rules when present.
        Default is $true.

    .PARAMETER Level
        Internal parameter for recursion level. Used for indentation.
        Users should not need to set this parameter directly.

    .PARAMETER GitIgnorePatterns
        Internal parameter for storing parsed .gitignore patterns.
        Users should not need to set this parameter directly.

    .EXAMPLE
        Show-Tree
        Shows the tree structure of the current directory

    .EXAMPLE
        Show-Tree -Path "C:\Projects\MyProject"
        Shows the tree structure of the specified directory

    .EXAMPLE
        Show-Tree -ExcludePattern @(".git", "node_modules", "*.log")
        Shows the tree structure excluding .git, node_modules directories and .log files

    .EXAMPLE
        Show-Tree -UseGitIgnore:$false
        Shows the tree structure without respecting .gitignore rules

    .NOTES
        This is a PowerShell implementation of the tree command with additional features
        like .gitignore support and flexible pattern matching.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = ".",
        
        [Parameter()]
        [string[]]$ExcludePattern = @(".git"),
        
        [Parameter()]
        [switch]$UseGitIgnore = $true,
        
        [Parameter()]
        [int]$Level = 0,
        
        [Parameter()]
        [System.Collections.Generic.List[string]]$GitIgnorePatterns
    )

    # Initialize GitIgnore patterns on first call (Level 0)
    if ($Level -eq 0 -and $UseGitIgnore -and -not $GitIgnorePatterns) {
        $GitIgnorePatterns = [System.Collections.Generic.List[string]]::new()

        # Check for .gitignore file in the path
        $gitIgnorePath = Join-Path -Path $Path -ChildPath ".gitignore"
        if (Test-Path $gitIgnorePath) {
            # Parse .gitignore file
            $gitIgnoreContent = Get-Content $gitIgnorePath

            foreach ($line in $gitIgnoreContent) {
                # Skip comments and empty lines
                if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.StartsWith('#')) {
                    # Normalize the pattern and add it to the list
                    $pattern = $line.Trim()
                    # Handle patterns that start with / (relative to repo root)
                    if ($pattern.StartsWith('/')) {
                        $pattern = $pattern.Substring(1)
                    }
                    $GitIgnorePatterns.Add($pattern)
                }
            }
        }
    }

    # Get the absolute path
    $absPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $absPath) { $absPath = $Path }

    # Get all items in the current directory
    $items = Get-ChildItem -Path $absPath -Force | Sort-Object { $_.PSIsContainer }, Name

    # Process each item
    foreach ($item in $items) {
        # Skip if the item matches an exclude pattern
        $skipItem = $false
        foreach ($pattern in $ExcludePattern) {
            if ($item.Name -like $pattern) {
                $skipItem = $true
                break
            }
        }

        # Check against gitignore patterns if enabled and not already skipped
        if (-not $skipItem -and $UseGitIgnore -and $GitIgnorePatterns) {
            # Get relative path from the base directory for gitignore matching
            $rootPath = (Resolve-Path $Path).Path
            $itemPath = $item.FullName
            
            # Convert paths to match pattern style (using forward slashes)
            $normalizedRootPath = $rootPath.Replace("\", "/")
            if (-not $normalizedRootPath.EndsWith("/")) {
                $normalizedRootPath += "/"
            }
            
            $normalizedItemPath = $itemPath.Replace("\", "/")
            $relativePath = $normalizedItemPath.Replace($normalizedRootPath, "")
            
            # Check the item against each gitignore pattern
            foreach ($pattern in $GitIgnorePatterns) {
                # Handle different pattern formats
                $isMatch = $false
                
                # Direct match
                if ($pattern -eq $relativePath -or $pattern -eq $item.Name) {
                    $isMatch = $true
                }
                # Pattern with / at end means directory only
                elseif ($pattern.EndsWith('/') -and $item.PSIsContainer -and ($relativePath -eq $pattern.TrimEnd('/') -or $item.Name -eq $pattern.TrimEnd('/'))) {
                    $isMatch = $true
                }
                # Pattern with wildcard at start
                elseif ($pattern.StartsWith('*') -and $relativePath.EndsWith($pattern.TrimStart('*'))) {
                    $isMatch = $true
                }
                # Plain pattern - check if it's anywhere in the path
                elseif ($relativePath -eq $pattern -or $relativePath.StartsWith("$pattern/") -or $item.Name -eq $pattern) {
                    $isMatch = $true
                }
                
                if ($isMatch) {
                    $skipItem = $true
                    break
                }
            }
        }

        if (-not $skipItem) {
            # Prepare the indentation
            $indent = "    " * $Level
            
            # Add the branch symbol
            if ($Level -gt 0) {
                $indent = $indent.Substring(0, $indent.Length - 4) + "├── "
            }
            
            # Output the item name with color based on type
            $displayName = $item.Name
            if ($item.PSIsContainer) {
                Write-Host "$indent$displayName/" -ForegroundColor Blue
            } else {
                Write-Host "$indent$displayName" -ForegroundColor White
            }
            
            # If it's a directory, recurse into it
            if ($item.PSIsContainer) {
                Show-Tree -Path $item.FullName -ExcludePattern $ExcludePattern -UseGitIgnore:$UseGitIgnore -Level ($Level + 1) -GitIgnorePatterns $GitIgnorePatterns
            }
        }
    }

    # If we're at the root level, print a summary
    if ($Level -eq 0) {
        # Create script-scoped variables for counting
        $script:fileCount = 0
        $script:dirCount = 0
        
        # Function to check if an item should be included based on patterns
        function ShouldIncludeItem {
            param(
                [Parameter(Mandatory=$true)]
                [System.IO.FileSystemInfo]$Item,
                
                [Parameter(Mandatory=$true)]
                [string]$RootPath
            )
            
            # Check exclude patterns
            foreach ($pattern in $ExcludePattern) {
                if ($Item.Name -like $pattern) {
                    return $false
                }
            }
            
            # Check gitignore patterns if enabled
            if ($UseGitIgnore -and $GitIgnorePatterns) {
                # Get relative path from the base directory for gitignore matching
                $normalizedRootPath = $RootPath.Replace("\", "/")
                if (-not $normalizedRootPath.EndsWith("/")) {
                    $normalizedRootPath += "/"
                }
                
                $normalizedItemPath = $Item.FullName.Replace("\", "/")
                $relativePath = $normalizedItemPath.Replace($normalizedRootPath, "")
                
                foreach ($pattern in $GitIgnorePatterns) {
                    # Direct match
                    if ($pattern -eq $relativePath -or $pattern -eq $Item.Name) {
                        return $false
                    }
                    # Directory match
                    elseif ($pattern.EndsWith('/') -and $Item.PSIsContainer -and ($relativePath -eq $pattern.TrimEnd('/') -or $Item.Name -eq $pattern.TrimEnd('/'))) {
                        return $false
                    }
                    # Pattern with wildcard at start
                    elseif ($pattern.StartsWith('*') -and $relativePath.EndsWith($pattern.TrimStart('*'))) {
                        return $false
                    }
                    # Plain pattern - check if it's anywhere in the path
                    elseif ($relativePath -eq $pattern -or $relativePath.StartsWith("$pattern/") -or $Item.Name -eq $pattern) {
                        return $false
                    }
                }
            }
            
            return $true
        }
        
        # Function to recursively count files and directories
        function Count-FilesAndDirs {
            param(
                [string]$CurrentPath,
                [string]$RootPath
            )
            
            $items = Get-ChildItem -Path $CurrentPath -Force
            
            foreach ($item in $items) {
                if (ShouldIncludeItem -Item $item -RootPath $RootPath) {
                    if ($item.PSIsContainer) {
                        $script:dirCount++
                        Count-FilesAndDirs -CurrentPath $item.FullName -RootPath $RootPath
                    } else {
                        $script:fileCount++
                    }
                }
            }
        }
        
        # Get the root path once
        $rootPath = (Resolve-Path $Path).Path
        
        # Count the root directory itself
        $rootDir = Get-Item -Path $rootPath -Force
        if ($rootDir.PSIsContainer) {
            Count-FilesAndDirs -CurrentPath $rootPath -RootPath $rootPath
        }
        
        Write-Host "`n$script:dirCount directories, $script:fileCount files" -ForegroundColor Cyan
    }
} 
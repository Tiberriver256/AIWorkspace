function Get-AzDOPipelineMigrationStatus {
    <#
    .SYNOPSIS
        Retrieves pipeline migration statistics comparing classic pipelines to YAML pipelines across organizations.

    .DESCRIPTION
        This function analyzes Azure DevOps pipelines across all organizations and projects to track 
        migration progress from classic build/release pipelines to YAML pipelines. It provides counts 
        and percentages at organization, project, and overall levels.

    .PARAMETER OrgNames
        Optional. Array of organization names to check. If not specified, checks all accessible organizations.

    .PARAMETER IncludeReleaseDefinitions
        Optional. Switch to include release definitions in the counts (classic release pipelines). Default is $true.

    .PARAMETER ExcludeDisabledPipelines
        Optional. Switch to exclude disabled pipelines from the counts. Default is $false.

    .PARAMETER GroupByProject
        Optional. Switch to group and display results by project. Default is $true.

    .PARAMETER Summary
        Optional. Switch to only show summary information without detailed breakdown. Default is $false.

    .EXAMPLE
        Get-AzDOPipelineMigrationStatus
        Returns migration status for all organizations and projects.

    .EXAMPLE
        Get-AzDOPipelineMigrationStatus -OrgNames "MyOrg1", "MyOrg2" -Summary
        Returns summary migration status for only the specified organizations.

    .EXAMPLE
        Get-AzDOPipelineMigrationStatus -IncludeReleaseDefinitions $false
        Returns migration status for build pipelines only (excluding release definitions).

    .NOTES
        This function requires:
        - VSTeam PowerShell module
        - Active Azure authentication with access to Azure DevOps
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$OrgNames,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeReleaseDefinitions = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$ExcludeDisabledPipelines,
        
        [Parameter(Mandatory = $false)]
        [bool]$GroupByProject = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$Summary
    )

    try {
        # Track current organization to restore at the end
        $originalOrgConnection = $null
        $originalProject = $null
        $info = Get-VSTeamInfo -ErrorAction SilentlyContinue
        if ($info.Account) {
            $originalOrgConnection = $info.Account
            if ($info.DefaultProject) {
                $originalProject = $info.DefaultProject
            }
        }

        # Initialize results object
        $results = [PSCustomObject]@{
            TotalOrganizations    = 0
            TotalProjects         = 0
            TotalClassicPipelines = 0
            TotalYamlPipelines    = 0
            TotalReleasePipelines = 0
            MigrationPercentage   = 0
            Organizations         = @()
        }

        # Get organizations
        if (-not $OrgNames) {
            Write-Verbose "Getting all accessible Azure DevOps organizations..."
            $organizations = Get-AzDOOrganizations -ReturnAsObject
            $OrgNames = $organizations | Select-Object -ExpandProperty Name
        }

        if (-not $OrgNames -or $OrgNames.Count -eq 0) {
            Write-Warning "No Azure DevOps organizations found or specified."
            return $results
        }

        $results.TotalOrganizations = $OrgNames.Count
        Write-Verbose "Found $($OrgNames.Count) organizations to analyze"

        # Process each organization
        foreach ($orgName in $OrgNames) {
            Write-Verbose "Processing organization: $orgName"
            
            # Connect to the organization
            try {
                Connect-AzDO -OrgName $orgName -ErrorAction Stop | Out-Null
                Write-Verbose "Connected to $orgName"
            }
            catch {
                Write-Warning "Could not connect to organization $orgName. Error: $_"
                continue
            }

            # Get all projects in this organization
            try {
                $projects = Get-AzDOProjects -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not get projects for organization $orgName. Error: $_"
                continue
            }

            if (-not $projects -or $projects.Count -eq 0) {
                Write-Warning "No projects found in organization $orgName"
                continue
            }

            # Filter out projects with empty names
            $projects = $projects | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) }
            
            Write-Verbose "Found $($projects.Count) projects in $orgName"
            $results.TotalProjects += $projects.Count

            # Create organization results object
            $orgResults = [PSCustomObject]@{
                Name                = $orgName
                ProjectCount        = $projects.Count
                ClassicPipelines    = 0
                YamlPipelines       = 0
                ReleasePipelines    = 0
                MigrationPercentage = 0
                Projects            = @()
            }

            # Process each project
            foreach ($project in $projects) {
                # Skip projects with null or empty names
                if ([string]::IsNullOrWhiteSpace($project.Name)) {
                    Write-Verbose "Skipping project with empty name"
                    continue
                }
                
                Write-Verbose "Processing project: $($project.Name) in $orgName"
                
                # Set current project
                try {
                    Set-VSTeamDefaultProject -Project $project.Name -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Warning "Could not set project $($project.Name). Error: $_"
                    continue
                }

                # Create project results object
                $projectResults = [PSCustomObject]@{
                    Name                = $project.Name
                    ClassicPipelines    = 0
                    YamlPipelines       = 0
                    ReleasePipelines    = 0
                    MigrationPercentage = 0
                }

                # Get build definitions (both classic and YAML)
                try {
                    Write-Verbose "Getting build definitions for project $($project.Name)..."
                    
                    # Use a more robust approach with error handling
                    $buildDefinitions = @()
                    $buildDefinitions = Get-BuildDefinitionsViaREST -ProjectName $project.Name
                    
                    Write-Verbose "Retrieved $($buildDefinitions.Count) build definitions from $($project.Name)"
                    
                    if ($null -ne $buildDefinitions) {
                        if ($ExcludeDisabledPipelines) {
                            $buildDefinitions = $buildDefinitions | Where-Object { $null -ne $_ -and $_.queueStatus -ne "disabled" }
                        }
                        
                        # Count classic and YAML build pipelines using process.type
                        # process.type: 1 = Classic (Designer), 2 = YAML
                        $classicBuilds = @($buildDefinitions | Where-Object { 
                                $null -ne $_ -and 
                            ($null -eq $_.process -or $_.process.type -eq 1)
                            })
                        
                        $yamlBuilds = @($buildDefinitions | Where-Object { 
                                $null -ne $_ -and 
                                $null -ne $_.process -and 
                                $_.process.type -eq 2
                            })
                        
                        $projectResults.ClassicPipelines = $classicBuilds.Count
                        $projectResults.YamlPipelines = $yamlBuilds.Count
                        
                        # Update organization totals
                        $orgResults.ClassicPipelines += $classicBuilds.Count
                        $orgResults.YamlPipelines += $yamlBuilds.Count
                        
                        # Update global totals
                        $results.TotalClassicPipelines += $classicBuilds.Count
                        $results.TotalYamlPipelines += $yamlBuilds.Count
                        
                        Write-Verbose "Project $($project.Name) has $($classicBuilds.Count) classic pipelines and $($yamlBuilds.Count) YAML pipelines"
                    }
                    else {
                        Write-Verbose "No build definitions found for project $($project.Name)"
                    }
                }
                catch {
                    Write-Warning "Could not get build definitions for project $($project.Name). Error: $($_.Exception.Message)"
                    Write-Verbose "Full error: $_"
                    # Continue processing even if we can't get build definitions
                }

                # Get release definitions (always classic)
                if ($IncludeReleaseDefinitions) {
                    try {
                        Write-Verbose "Getting release definitions for project $($project.Name)..."
                        $releaseDefinitions = Get-VSTeamReleaseDefinition -ProjectName $project.Name -ErrorAction Stop
                        
                        if ($null -ne $releaseDefinitions) {
                            if ($ExcludeDisabledPipelines) {
                                # Filter disabled release pipelines
                                $releaseDefinitions = $releaseDefinitions | Where-Object { $null -ne $_ -and $_.isDisabled -ne $true }
                            }
                            
                            $projectResults.ReleasePipelines = $releaseDefinitions.Count
                            $orgResults.ReleasePipelines += $releaseDefinitions.Count
                            $results.TotalReleasePipelines += $releaseDefinitions.Count
                            
                            # Add release pipelines to classic count for migration percentage calculation
                            $projectResults.ClassicPipelines += $releaseDefinitions.Count
                            $orgResults.ClassicPipelines += $releaseDefinitions.Count
                            $results.TotalClassicPipelines += $releaseDefinitions.Count
                            
                            Write-Verbose "Project $($project.Name) has $($releaseDefinitions.Count) release pipelines"
                        }
                        else {
                            Write-Verbose "No release definitions found for project $($project.Name)"
                        }
                    }
                    catch {
                        Write-Warning "Could not get release definitions for project $($project.Name). Error: $($_.Exception.Message)"
                        # Continue processing even if we can't get release definitions
                    }
                }

                # Calculate project migration percentage
                $totalProjectPipelines = $projectResults.ClassicPipelines + $projectResults.YamlPipelines
                if ($totalProjectPipelines -gt 0) {
                    $projectResults.MigrationPercentage = [math]::Round(($projectResults.YamlPipelines / $totalProjectPipelines) * 100, 2)
                }

                # Add to organization projects array
                $orgResults.Projects += $projectResults
            }

            # Calculate organization migration percentage
            $totalOrgPipelines = $orgResults.ClassicPipelines + $orgResults.YamlPipelines
            if ($totalOrgPipelines -gt 0) {
                $orgResults.MigrationPercentage = [math]::Round(($orgResults.YamlPipelines / $totalOrgPipelines) * 100, 2)
            }

            # Add to results
            $results.Organizations += $orgResults
        }

        # Calculate overall migration percentage
        $totalPipelines = $results.TotalClassicPipelines + $results.TotalYamlPipelines
        if ($totalPipelines -gt 0) {
            $results.MigrationPercentage = [math]::Round(($results.TotalYamlPipelines / $totalPipelines) * 100, 2)
        }

        # Format and display results
        if ($Summary) {
            # Display only summary
            $summaryOutput = [PSCustomObject]@{
                TotalOrganizations         = $results.TotalOrganizations
                TotalProjects              = $results.TotalProjects
                TotalClassicBuildPipelines = $results.TotalClassicPipelines - $results.TotalReleasePipelines
                TotalYamlPipelines         = $results.TotalYamlPipelines
                TotalReleasePipelines      = $results.TotalReleasePipelines
                TotalPipelines             = $totalPipelines
                MigrationPercentage        = $results.MigrationPercentage
            }
            
            $summaryOutput | Format-List
        }
        elseif ($GroupByProject) {
            # Group by organization and then project
            foreach ($org in $results.Organizations) {
                Write-Host "`nOrganization: $($org.Name)" -ForegroundColor Cyan
                Write-Host "  Migration Progress: $($org.MigrationPercentage)% YAML (of $($org.ClassicPipelines + $org.YamlPipelines) total pipelines)"
                Write-Host "  Classic Builds: $($org.ClassicPipelines - $org.ReleasePipelines)"
                Write-Host "  YAML Pipelines: $($org.YamlPipelines)"
                if ($IncludeReleaseDefinitions) {
                    Write-Host "  Release Pipelines: $($org.ReleasePipelines)`n"
                }
                
                foreach ($proj in $org.Projects) {
                    Write-Host "  Project: $($proj.Name)" -ForegroundColor Yellow
                    Write-Host "    Migration Progress: $($proj.MigrationPercentage)% YAML"
                    Write-Host "    Classic Builds: $($proj.ClassicPipelines - $proj.ReleasePipelines)"
                    Write-Host "    YAML Pipelines: $($proj.YamlPipelines)"
                    if ($IncludeReleaseDefinitions) {
                        Write-Host "    Release Pipelines: $($proj.ReleasePipelines)"
                    }
                }
            }
            
            # Show overall summary
            Write-Host "`n========== OVERALL SUMMARY ==========" -ForegroundColor Green
            Write-Host "Total Organizations: $($results.TotalOrganizations)"
            Write-Host "Total Projects: $($results.TotalProjects)"
            Write-Host "Migration Progress: $($results.MigrationPercentage)% YAML"
            Write-Host "Classic Build Pipelines: $($results.TotalClassicPipelines - $results.TotalReleasePipelines)"
            Write-Host "YAML Pipelines: $($results.TotalYamlPipelines)"
            if ($IncludeReleaseDefinitions) {
                Write-Host "Release Pipelines: $($results.TotalReleasePipelines)"
            }
            Write-Host "======================================`n"
        }
        else {
            # Return the full results object
            $results
        }

        # Restore original connection
        if ($originalOrgConnection) {
            try {
                Connect-AzDO -OrgName $originalOrgConnection | Out-Null
                if (-not [string]::IsNullOrWhiteSpace($originalProject)) {
                    Set-VSTeamDefaultProject -Project $originalProject | Out-Null
                }
                Write-Verbose "Restored connection to original organization: $originalOrgConnection"
            }
            catch {
                Write-Warning "Could not restore original connection to $originalOrgConnection"
            }
        }

        return $results
    }
    catch {
        # Restore original connection on error
        if ($originalOrgConnection) {
            try {
                Connect-AzDO -OrgName $originalOrgConnection | Out-Null
                if (-not [string]::IsNullOrWhiteSpace($originalProject)) {
                    Set-VSTeamDefaultProject -Project $originalProject | Out-Null
                }
            }
            catch {
                Write-Warning "Could not restore original connection to $originalOrgConnection"
            }
        }
        
        Write-Error "An error occurred in Get-AzDOPipelineMigrationStatus: $($_.Exception.Message)"
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
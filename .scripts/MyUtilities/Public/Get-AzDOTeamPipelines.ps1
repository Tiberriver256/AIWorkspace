function Get-AzDOTeamPipelines {
    <#
    .SYNOPSIS
        Lists pipelines (build definitions) associated with a team in Azure DevOps.

    .DESCRIPTION
        This function finds and lists build pipelines that are associated with a specific team
        by checking pipeline names, paths, or repository association.
        It can include recent pipeline runs and provides detailed information about each pipeline.

    .PARAMETER TeamName
        The name of the team to find pipelines for.

    .PARAMETER ProjectName
        Optional. The project name. If not specified, uses the default project.

    .PARAMETER OrgName
        Optional. The organization to connect to if not already connected.

    .PARAMETER IncludeRuns
        Optional. If true, includes recent pipeline runs. Default is true.

    .PARAMETER RunsToShow
        Optional. Number of recent runs to show for each pipeline. Default is 3.

    .EXAMPLE
        Get-AzDOTeamPipelines -TeamName "MyTeam"
        Lists pipelines associated with the MyTeam team in the default project.

    .EXAMPLE
        Get-AzDOTeamPipelines -TeamName "MyTeam" -ProjectName "MyProject" -OrgName "MyOrganization" -IncludeRuns $false
        Lists pipelines for the MyTeam team without showing recent runs.

    .EXAMPLE
        Get-AzDOTeamPipelines -TeamName "DevTeam" -RunsToShow 5 | ConvertTo-Json -Depth 5
        Gets pipelines for DevTeam with their 5 most recent runs and outputs as JSON.

    .NOTES
        This function requires:
        - VSTeam PowerShell module
        - Active connection to Azure DevOps (use Connect-AzDO first)

        The function considers a pipeline to be associated with a team if:
        - The pipeline name contains the team name
        - The pipeline path contains the team name
        - The repository branch contains the team name
        - The YAML file path contains the team name
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
        [bool]$IncludeRuns = $true,
        
        [Parameter(Mandatory = $false)]
        [int]$RunsToShow = 3
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
        Write-Verbose "Searching for pipelines associated with team '$TeamName' in project '$project'..."
        
        # Get all build definitions
        $definitions = Get-VSTeamBuildDefinition -ProjectName $project -ErrorAction Stop
        
        if (-not $definitions -or $definitions.Count -eq 0) {
            Write-Warning "No build definitions found in project '$project'."
            return
        }
        
        # Get all repositories for checking folder paths
        $repos = Get-VSTeamGitRepository -ProjectName $project -ErrorAction SilentlyContinue
        
        # Find build definitions that might be associated with the team
        $teamPipelines = $definitions | Where-Object {
            # Check if pipeline name contains team name
            $_.name -like "*$TeamName*" -or
            
            # Check if pipeline path contains team name
            $_.path -like "*$TeamName*" -or
            
            # Check repository folder paths if available
            ($_.repository -and $_.repository.defaultBranch -like "*$TeamName*") -or
            
            # Check for team name in the YAML file path if it's a YAML pipeline
            ($_.process -and $_.process.yamlFilename -and $_.process.yamlFilename -like "*$TeamName*")
        }
        
        # Create results object
        $results = [PSCustomObject]@{
            TeamName       = $TeamName
            Project        = $project
            PipelinesCount = $teamPipelines.Count
            Pipelines      = @()
        }
        
        if ($teamPipelines.Count -eq 0) {
            Write-Warning "No pipelines found that are associated with team '$TeamName'."
            return $results
        }
        
        Write-Verbose "Found $($teamPipelines.Count) pipelines associated with team '$TeamName'"
        
        # Process each pipeline
        foreach ($pipeline in $teamPipelines) {
            $pipelineInfo = [PSCustomObject]@{
                Id             = $pipeline.id
                Name           = $pipeline.name
                Path           = $pipeline.path
                CreatedBy      = $pipeline.authoredBy.displayName
                CreatedDate    = $pipeline.createdDate
                Type           = if ($pipeline.process.yamlFilename) { "YAML" } else { "Classic" }
                YamlPath       = $pipeline.process.yamlFilename
                RepositoryName = $pipeline.repository.name
                RepositoryType = $pipeline.repository.type
                DefaultBranch  = $pipeline.repository.defaultBranch
                WebUrl         = $pipeline.url
                Runs           = $null
            }
            
            # Get recent builds if requested
            if ($IncludeRuns) {
                try {
                    Write-Verbose "Getting recent runs for pipeline '$($pipeline.name)'"
                    $runs = Get-VSTeamBuild -ProjectName $project -DefinitionId $pipeline.id -Top $RunsToShow |
                    Select-Object buildNumber, 
                    status, 
                    result, 
                    startTime, 
                    finishTime, 
                    @{Name = "RequestedBy"; Expression = { $_.requestedFor.displayName } },
                    @{Name = "URL"; Expression = { $_.url } }
                    $pipelineInfo.Runs = $runs
                }
                catch {
                    Write-Warning "Could not retrieve runs for pipeline '$($pipeline.name)': $_"
                }
            }
            
            $results.Pipelines += $pipelineInfo
        }
        
        # Display a summary
        Write-Verbose ($results | ConvertTo-Json -Depth 3)
        
        return $results
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
} 
function Get-AzDOPipelineFailureInfo {
    <#
    .SYNOPSIS
        Gathers comprehensive information about an Azure DevOps pipeline failure.
    
    .DESCRIPTION
        This function collects detailed information about an Azure DevOps pipeline failure, 
        including error details, environment information, source control data, variables, 
        artifacts, and logs. It provides an issue summary that highlights the most relevant 
        information for troubleshooting.

        The function is designed to be resilient to partial data availability, handling null values
        and missing information gracefully to ensure it can collect as much data as possible even
        when the pipeline run is incomplete or has limited available information.
    
    .PARAMETER Organization
        The Azure DevOps organization name.
    
    .PARAMETER Project
        The Azure DevOps project name.
    
    .PARAMETER PipelineId
        The ID of the pipeline.
    
    .PARAMETER RunId
        The ID of the pipeline run.
    
    .PARAMETER PipelineUrl
        The URL of the failing pipeline run. Can be used instead of specifying individual parameters.
        Supports both classic and modern Azure DevOps URL formats.
    
    .EXAMPLE
        Get-AzDOPipelineFailureInfo -Organization "contoso" -Project "MyProject" -PipelineId 42 -RunId 123
    
    .EXAMPLE
        Get-AzDOPipelineFailureInfo -PipelineUrl "https://dev.azure.com/contoso/MyProject/_pipelines/pipelines/42/runs/123"
    
    .LINK
        https://learn.microsoft.com/en-us/rest/api/azure/devops/pipelines/runs/get?view=azure-devops-rest-7.1
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByParameters')]
    param (
        # Parameter set for individual components
        [Parameter(Mandatory = $true, ParameterSetName = 'ByParameters')]
        [string]$Organization,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'ByParameters')]
        [string]$Project,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'ByParameters')]
        [string]$PipelineId,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'ByParameters')]
        [string]$RunId,

        # Parameter set for URL
        [Parameter(Mandatory = $true, 
                 ParameterSetName = 'ByUrl',
                 Position = 0,
                 HelpMessage = 'The URL of the failing pipeline run')]
        [ValidatePattern('^https:\/\/dev\.azure\.com\/[^\/]+\/[^\/]+\/_(?:build\/results\?buildId=\d+|pipelines\/pipelines\/\d+\/runs\/\d+)')]
        [string]$PipelineUrl
    )

    begin {
        # Load System.Web for URL decoding
        Add-Type -AssemblyName System.Web
        
        Write-Verbose "Starting Get-AzDOPipelineFailureInfo"
        
        if ($PSCmdlet.ParameterSetName -eq 'ByUrl') {
            # Parse URL to extract organization, project, pipeline ID, and run ID
            $urlPattern = @{
                # Classic URL pattern
                Classic = '^https:\/\/dev\.azure\.com\/(?<organization>[^\/]+)\/(?<project>[^\/]+)\/_build\/results\?buildId=(?<runId>\d+)'
                # Modern URL pattern
                Modern = '^https:\/\/dev\.azure\.com\/(?<organization>[^\/]+)\/(?<project>[^\/]+)\/_pipelines\/pipelines\/(?<pipelineId>\d+)\/runs\/(?<runId>\d+)'
            }

            Write-Verbose "Parsing URL: $PipelineUrl"
            $urlParsed = $false
            
            foreach ($pattern in $urlPattern.Values) {
                if ($PipelineUrl -match $pattern) {
                    $Organization = $matches['organization']
                    $Project = [System.Web.HttpUtility]::UrlDecode($matches['project'])
                    $RunId = $matches['runId']
                    if ($matches['pipelineId']) {
                        $PipelineId = $matches['pipelineId']
                    }
                    $urlParsed = $true
                    Write-Verbose "URL parsed successfully: Org=$Organization, Project=$Project, RunId=$RunId"
                    break
                }
            }

            if (-not $urlParsed) {
                throw "Unable to parse pipeline URL. Please ensure it's a valid Azure DevOps pipeline URL."
            }
            
            # For classic URLs, we'll need to query the API to get the pipeline ID from the run ID
            if (-not $PipelineId) {
                Write-Verbose "Classic URL detected. Querying API to get pipeline ID from run ID."
                try {
                    $buildInfo = Invoke-RestMethod -Uri "https://dev.azure.com/$Organization/$Project/_apis/build/builds/$RunId`?api-version=7.1" -UseDefaultCredentials
                    $PipelineId = $buildInfo.definition.id
                    Write-Verbose "Retrieved pipeline ID: $PipelineId"
                }
                catch {
                    throw "Failed to retrieve pipeline ID from run ID: $_"
                }
            }
        }
    }

    process {
        try {
            Write-Verbose "Collecting failure information for pipeline $PipelineId, run $RunId in $Organization/$Project"
            
            # Verify connection and authentication to Azure DevOps
            try {
                Get-VSTeamProject -Project $Project -ErrorAction Stop | Out-Null
                Write-Verbose "Connection to Azure DevOps verified"
            }
            catch {
                Write-Verbose "Connection to Azure DevOps not established. Attempting to connect."
                try {
                    # Try to use existing Connect-AzDO function if available
                    if (Get-Command 'Connect-AzDO' -ErrorAction SilentlyContinue) {
                        Connect-AzDO -Organization $Organization
                    }
                    else {
                        # Fallback to VSTeam module direct connection
                        Set-VSTeamAccount -Account $Organization -UseWindowsAuthentication
                    }
                    Write-Verbose "Successfully connected to Azure DevOps"
                }
                catch {
                    throw "Failed to authenticate to Azure DevOps: $_"
                }
            }

            # 1. Get pipeline run details
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Retrieving pipeline run details" -PercentComplete 10
            $pipelineRun = Get-VSTeamBuild -BuildId $RunId -ProjectName $Project
            
            if (-not $pipelineRun) {
                throw "Pipeline run with ID $RunId not found in project $Project"
            }
            
            $pipelineInfo = @{
                Name        = $pipelineRun.definition.name ?? "Unknown"
                Id          = $PipelineId
                RunId       = $RunId
                Status      = $pipelineRun.status ?? "Unknown"
                Result      = $pipelineRun.result ?? "Unknown"
                StartTime   = $pipelineRun.startTime
                FinishTime  = $pipelineRun.finishTime
                Duration    = if ($pipelineRun.finishTime -and $pipelineRun.startTime) {
                    New-TimeSpan -Start $pipelineRun.startTime -End $pipelineRun.finishTime
                } else { $null }
                Trigger     = $pipelineRun.reason ?? "Unknown"
                RequestedBy = $pipelineRun.requestedBy.displayName ?? "Unknown"
                URL         = if ($pipelineRun._links.web.href) { $pipelineRun._links.web.href } else { "https://dev.azure.com/$Organization/$Project/_build/results?buildId=$RunId" }
            }
            
            # 2. Get failure details
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Retrieving failure details" -PercentComplete 20
            
            $timeline = $null
            $failedStages = @()
            $failedTasks = @()
            
            Write-Verbose "Checking timeline link availability..."
            Write-Verbose "Pipeline run _links: $($pipelineRun._links | ConvertTo-Json -Depth 1)"
            
            # Check if timeline link exists
            if ($pipelineRun._links -and 
                $pipelineRun._links.PSObject.Properties.Name -contains 'timeline' -and 
                $pipelineRun._links.timeline -and 
                $pipelineRun._links.timeline.PSObject.Properties.Name -contains 'href' -and
                -not [string]::IsNullOrEmpty($pipelineRun._links.timeline.href)) {
                
                # Ensure we have an absolute URI for timeline
                $timelineUrl = $pipelineRun._links.timeline.href
                Write-Verbose "Original timeline URL: $timelineUrl"
                
                if (-not ([string]::IsNullOrEmpty($timelineUrl)) -and -not $timelineUrl.StartsWith("http")) {
                    $timelineUrl = "https://dev.azure.com/$Organization/$Project/_apis" + $timelineUrl
                    Write-Verbose "Adjusted timeline URL to absolute path: $timelineUrl"
                }
                $timelineUrl = $timelineUrl + "?api-version=7.1"
                Write-Verbose "Final timeline URL with API version: $timelineUrl"
                
                try {
                    Write-Verbose "Retrieving timeline data..."
                    $timeline = Invoke-RestMethod -Uri $timelineUrl -UseDefaultCredentials
                    Write-Verbose "Timeline data retrieved successfully. Record count: $($timeline.count)"
                    
                    $failedStages = $timeline.records | Where-Object { ($_.type -eq 'Stage' -or $_.type -eq 'Phase') -and $_.result -eq 'failed' }
                    $failedTasks = $timeline.records | Where-Object { $_.type -eq 'Task' -and $_.result -eq 'failed' }
                    
                    Write-Verbose "Found $($failedStages.Count) failed stages and $($failedTasks.Count) failed tasks"
                    
                    # Sort tasks by most recently failed
                    $failedTasks = $failedTasks | Sort-Object -Property finishTime -Descending
                }
                catch {
                    Write-Warning "Failed to retrieve timeline data: $_"
                    Write-Verbose "Timeline retrieval error details: $($_.Exception.Message)"
                }
            }
            else {
                Write-Warning "Timeline data not available for this pipeline run."
                Write-Verbose "Timeline link validation failed:"
                Write-Verbose "Has _links: $($null -ne $pipelineRun._links)"
                Write-Verbose "Has timeline property: $($pipelineRun._links.PSObject.Properties.Name -contains 'timeline')"
                if ($pipelineRun._links.PSObject.Properties.Name -contains 'timeline') {
                    Write-Verbose "Timeline object exists: $($null -ne $pipelineRun._links.timeline)"
                    Write-Verbose "Timeline href exists: $($pipelineRun._links.timeline.PSObject.Properties.Name -contains 'href')"
                    Write-Verbose "Timeline href not empty: $(-not [string]::IsNullOrEmpty($pipelineRun._links.timeline.href))"
                }
            }
            
            $failureDetails = @{
                FailedStages = $failedStages | ForEach-Object {
                    @{
                        Name      = $_.name
                        Id        = $_.id
                        StartTime = $_.startTime
                        EndTime   = $_.finishTime
                        Log       = $_.log
                    }
                }
                FailedTasks  = $failedTasks | ForEach-Object {
                    @{
                        Name      = $_.name
                        Id        = $_.id
                        StartTime = $_.startTime
                        EndTime   = $_.finishTime
                        Log       = $_.log
                        Issues    = $_.issues
                        ParentId  = $_.parentId
                    }
                }
                ErrorCount   = ($failedTasks | ForEach-Object { $_.issues.Count } | Measure-Object -Sum).Sum
                ErrorLogs    = $failedTasks | ForEach-Object {
                    if ($_ -and 
                        $_.PSObject.Properties.Name -contains 'log' -and 
                        $_.log -and 
                        $_.log.PSObject.Properties.Name -contains 'url' -and
                        -not [string]::IsNullOrEmpty($_.log.url)) {
                        
                        $logContent = $null
                        try {
                            $logUrl = $_.log.url
                            if (-not [string]::IsNullOrEmpty($logUrl) -and -not $logUrl.StartsWith("http")) {
                                $logUrl = "https://dev.azure.com/$Organization/$Project/_apis" + $logUrl
                            }
                            $logUrl = $logUrl + "?api-version=7.1"
                            
                            $logContent = Invoke-RestMethod -Uri $logUrl -UseDefaultCredentials
                        }
                        catch {
                            $logContent = "Failed to retrieve log: $_"
                        }
                        @{
                            TaskName = $_.name
                            Content  = $logContent
                        }
                    }
                }
            }
            
            # 3. Get environment information
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Retrieving environment information" -PercentComplete 30
            $environmentInfo = @{
                AgentName     = $pipelineRun.agent.name ?? "Unknown"
                AgentId       = $pipelineRun.agent.id ?? "Unknown"
                PoolName      = $pipelineRun.queue.name ?? "Unknown"
                PoolId        = $pipelineRun.queue.id ?? "Unknown"
                Demands       = if ($pipelineRun.demands) { $pipelineRun.demands } else { @() }
                JobTimeoutInMinutes = $pipelineRun.jobTimeoutInMinutes ?? 0
            }
            
            # 4. Get source control information
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Retrieving source control information" -PercentComplete 40
            $sourceInfo = @{
                Type          = $pipelineRun.repository.type ?? "Unknown"
                RepoName      = $pipelineRun.repository.name ?? "Unknown"
                RepoId        = $pipelineRun.repository.id ?? "Unknown"
                Branch        = if ($pipelineRun.sourceBranch) { $pipelineRun.sourceBranch -replace '^refs/heads/', '' } else { "Unknown" }
                CommitId      = $pipelineRun.sourceVersion ?? "Unknown"
                CommitMessage = $pipelineRun.sourceVersionMessage ?? "No message"
                RecentCommits = @()
            }
            
            # Get recent commits if repository information is available
            if ($pipelineRun.repository -and $pipelineRun.repository.id -and $sourceInfo.Branch) {
                try {
                    $commitsUrl = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories/$($pipelineRun.repository.id)/commits?searchCriteria.itemVersion.version=$($sourceInfo.Branch)&searchCriteria.`$top=10&api-version=7.1"
                    $commits = Invoke-RestMethod -Uri $commitsUrl -UseDefaultCredentials
                    $sourceInfo.RecentCommits = $commits.value | Select-Object -Property commitId, comment, author, committer, commitTime
                }
                catch {
                    Write-Warning "Failed to retrieve recent commits: $_"
                    $sourceInfo.RecentCommits = "Failed to retrieve"
                }
            }
            else {
                Write-Warning "Repository information incomplete. Cannot retrieve commit history."
            }
            
            # 5. Get variable information
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Retrieving variable information" -PercentComplete 50
            $variableInfo = @{
                PipelineVariables = @()
                SystemVariables   = @()
            }
            
            # Get pipeline definition to extract variables
            try {
                $pipelineDefUrl = "https://dev.azure.com/$Organization/$Project/_apis/build/definitions/$PipelineId`?api-version=7.1"
                Write-Verbose "Retrieving pipeline definition from: $pipelineDefUrl"
                Write-Verbose "Pipeline ID being used: $PipelineId"
                
                $pipelineDefinition = Invoke-RestMethod -Uri $pipelineDefUrl -UseDefaultCredentials
                Write-Verbose "Pipeline definition retrieved. Checking for variables..."
                Write-Verbose "Definition properties: $($pipelineDefinition.PSObject.Properties.Name -join ', ')"
                
                if ($pipelineDefinition.PSObject.Properties.Name -contains 'variables' -and $pipelineDefinition.variables) {
                    Write-Verbose "Variables found in definition. Processing..."
                    Write-Verbose "Variable names found: $($pipelineDefinition.variables | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)"
                    
                    $variableInfo.PipelineVariables = $pipelineDefinition.variables | 
                        Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue | 
                        ForEach-Object {
                            $name = $_.Name
                            @{
                                Name   = $name
                                Value  = if ($pipelineDefinition.variables.$name.isSecret) { "***SECRET***" } else { $pipelineDefinition.variables.$name.value }
                                Secret = $pipelineDefinition.variables.$name.isSecret
                            }
                        }
                    Write-Verbose "Processed $($variableInfo.PipelineVariables.Count) pipeline variables"
                }
                else {
                    Write-Warning "No pipeline variables found in the definition."
                    Write-Verbose "Variables property exists: $($pipelineDefinition.PSObject.Properties.Name -contains 'variables')"
                    Write-Verbose "Variables not null: $($null -ne $pipelineDefinition.variables)"
                }
            }
            catch {
                Write-Warning "Failed to retrieve pipeline variables: $_"
                Write-Verbose "Pipeline variables retrieval error details: $($_.Exception.Message)"
                if ($_.Exception.Response) {
                    Write-Verbose "Response status code: $($_.Exception.Response.StatusCode.value__)"
                }
            }
            
            # 6. Get artifact information
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Retrieving artifact information" -PercentComplete 70
            try {
                $artifactUrl = "https://dev.azure.com/$Organization/$Project/_apis/build/builds/$RunId/artifacts?api-version=7.1"
                Write-Verbose "Retrieving artifacts from: $artifactUrl"
                
                $artifacts = Invoke-RestMethod -Uri $artifactUrl -UseDefaultCredentials
                Write-Verbose "Artifacts response received. Checking content..."
                Write-Verbose "Artifacts response properties: $($artifacts.PSObject.Properties.Name -join ', ')"
                
                if ($artifacts.PSObject.Properties.Name -contains 'value' -and $artifacts.value) {
                    Write-Verbose "Found $($artifacts.value.Count) artifacts"
                    $artifactInfo = $artifacts.value | ForEach-Object {
                        @{
                            Name     = $_.name ?? "Unknown"
                            Resource = if ($_.resource) { $_.resource } else { @{} }
                            Download = $_.downloadUrl ?? ""
                        }
                    }
                    Write-Verbose "Processed $($artifactInfo.Count) artifacts"
                }
                else {
                    Write-Warning "No artifacts found for this pipeline run."
                    Write-Verbose "Value property exists: $($artifacts.PSObject.Properties.Name -contains 'value')"
                    Write-Verbose "Value not null: $($null -ne $artifacts.value)"
                }
            }
            catch {
                Write-Warning "Failed to retrieve artifacts: $_"
                Write-Verbose "Artifacts retrieval error details: $($_.Exception.Message)"
                if ($_.Exception.Response) {
                    Write-Verbose "Response status code: $($_.Exception.Response.StatusCode.value__)"
                }
            }
            
            # 7. Get logs
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Retrieving logs" -PercentComplete 80
            $logInfo = @{
                BuildLogs = try {
                    $buildLogsUrl = "https://dev.azure.com/$Organization/$Project/_apis/build/builds/$RunId/logs?api-version=7.1"
                    $buildLogs = Invoke-RestMethod -Uri $buildLogsUrl -UseDefaultCredentials
                    if ($buildLogs.PSObject.Properties.Name -contains 'value' -and $buildLogs.value) {
                        $buildLogs.value | ForEach-Object {
                            $logId = $_.id
                            $logUrl = "https://dev.azure.com/$Organization/$Project/_apis/build/builds/$RunId/logs/$logId`?api-version=7.1"
                            @{
                                Id      = $logId
                                Url     = $logUrl
                                Name    = $_.name ?? "Unknown"
                                Type    = $_.type ?? "Unknown"
                                Content = "Log content not retrieved to reduce payload size"
                            }
                        }
                    }
                    else {
                        Write-Warning "No build logs found for this pipeline run."
                        @()
                    }
                }
                catch {
                    Write-Warning "Failed to retrieve build logs: $_"
                    @()
                }
            }
            
            # 8. Create issue summary
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Creating issue summary" -PercentComplete 90
            
            # Determine failure type
            $failureType = "Unknown"
            if ($failedTasks.Count -gt 0) {
                $primaryTask = $failedTasks[0]
                if ($primaryTask.name -match "Test|VSTest|MSTest|NUnit|XUnit") {
                    $failureType = "Test Failure"
                }
                elseif ($primaryTask.name -match "Build|MSBuild|Compile|Maven|Gradle") {
                    $failureType = "Build Error"
                }
                elseif ($primaryTask.name -match "Deploy|Release|Publish|Azure|ARM|Terraform") {
                    $failureType = "Deployment Error"
                }
                elseif ($primaryTask.name -match "Docker|Container|ACR|Image") {
                    $failureType = "Container Error"
                }
                elseif ($primaryTask.name -match "Npm|Yarn|Node|Package") {
                    $failureType = "Package Manager Error"
                }
                else {
                    $failureType = "Task Failure"
                }
            }
            
            # Get primary error
            $primaryError = ""
            if ($failedTasks.Count -gt 0 -and $failedTasks[0].issues.Count -gt 0) {
                $primaryError = $failedTasks[0].issues[0].message
            }
            elseif ($failureDetails.ErrorLogs -and $failureDetails.ErrorLogs.Count -gt 0) {
                # Try to extract error from logs
                $logContent = $failureDetails.ErrorLogs[0].Content
                if ($logContent -is [string] -and $logContent -match "(?:error|exception|fail).*?:(.+?)(?:\r?\n|$)") {
                    $primaryError = $matches[1].Trim()
                }
            }
            
            # Identify possible causes based on error patterns
            $possibleCauses = @()
            
            if ($primaryError -match "permission|access denied|unauthorized|auth") {
                $possibleCauses += "Insufficient permissions or authorization issues"
            }
            if ($primaryError -match "timeout|timed out") {
                $possibleCauses += "Operation timed out - may need increased timeout limits"
            }
            if ($primaryError -match "memory|out of memory|heap") {
                $possibleCauses += "Memory limitations or leaks"
            }
            if ($primaryError -match "not found|404|could not find|doesn't exist") {
                $possibleCauses += "Missing resources or dependencies"
            }
            if ($primaryError -match "version|dependency|incompatible") {
                $possibleCauses += "Version conflicts or incompatible dependencies"
            }
            if ($primaryError -match "network|connectivity|connection refused|unreachable") {
                $possibleCauses += "Network or connectivity issues"
            }
            if ($primaryError -match "syntax|parsing|unexpected token|invalid") {
                $possibleCauses += "Syntax errors or invalid configuration"
            }
            
            # If no specific pattern was found, add a generic cause
            if ($possibleCauses.Count -eq 0) {
                $possibleCauses += "Unknown error - review logs for details"
            }
            
            # Identify affected resources
            $affectedResources = @()
            
            if ($primaryError -match "(?:path|file|directory):?\s*['\""]?([^'\""\r\n]+)['\""]?") {
                $affectedResources += "File: $($matches[1])"
            }
            if ($primaryError -match "(?:database|db|sql):?\s*['\""]?([^'\""\r\n]+)['\""]?") {
                $affectedResources += "Database: $($matches[1])"
            }
            if ($primaryError -match "(?:server|host|endpoint):?\s*['\""]?([^'\""\r\n]+)['\""]?") {
                $affectedResources += "Server: $($matches[1])"
            }
            if ($primaryError -match "(?:container|image):?\s*['\""]?([^'\""\r\n]+)['\""]?") {
                $affectedResources += "Container: $($matches[1])"
            }
            if ($primaryError -match "(?:service|api):?\s*['\""]?([^'\""\r\n]+)['\""]?") {
                $affectedResources += "Service: $($matches[1])"
            }
            
            $issueSummary = @{
                FailureType       = $failureType
                PrimaryError      = $primaryError
                FailedStage       = if ($failedStages.Count -gt 0) { $failedStages[0].name } else { "Unknown" }
                FailedTask        = if ($failedTasks.Count -gt 0) { $failedTasks[0].name } else { "Unknown" }
                TimeOfFailure     = if ($failedTasks.Count -gt 0 -and $failedTasks[0].finishTime) { 
                                        $failedTasks[0].finishTime 
                                    } 
                                    elseif ($pipelineRun.finishTime) { 
                                        $pipelineRun.finishTime 
                                    } 
                                    else { 
                                        Get-Date 
                                    }
                RecentChanges     = @()
                PossibleCauses    = $possibleCauses
                AffectedResources = $affectedResources
            }
            
            # Add recent changes if available
            if ($sourceInfo.RecentCommits -and $sourceInfo.RecentCommits -isnot [string]) {
                $issueSummary.RecentChanges = $sourceInfo.RecentCommits | 
                                              Select-Object -First 3 | 
                                              ForEach-Object {
                    if ($_ -is [PSCustomObject] -or $_ -is [Hashtable]) {
                        $commitTime = if ($_.commitTime) { $_.commitTime } else { "Unknown" }
                        $authorName = if ($_.author.name) { $_.author.name } else { "Unknown" }
                        $comment = if ($_.comment) { $_.comment.Split("`n")[0] } else { "No comment" }
                        
                        "$commitTime - $authorName" + ": $comment"
                    }
                    else { 
                        "Unknown commit information" 
                    }
                }
            }
            
            # 9. Combine all information
            Write-Progress -Activity "Gathering Azure DevOps Pipeline Failure Info" -Status "Completed" -PercentComplete 100
            
            $result = [PSCustomObject]@{
                IssueSummary   = $issueSummary
                PipelineInfo   = $pipelineInfo
                FailureDetails = $failureDetails
                Environment    = $environmentInfo
                SourceControl  = $sourceInfo
                Variables      = $variableInfo
                Artifacts      = $artifactInfo
                Logs           = $logInfo
            }
            
            return $result
        }
        catch {
            Write-Error "Error gathering Azure DevOps pipeline failure information: $_"
            throw
        }
    }
} 
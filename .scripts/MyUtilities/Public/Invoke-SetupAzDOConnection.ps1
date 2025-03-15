function Invoke-SetupAzDOConnection {
    <#
    .SYNOPSIS
        Interactive setup for connecting to Azure DevOps.
    .DESCRIPTION
        This function guides the user through the process of selecting an Azure DevOps organization
        and project, then establishes a connection for subsequent Azure DevOps operations.
    .EXAMPLE
        Invoke-SetupAzDOConnection
        Interactively prompts the user to select an organization and project, then connects to it.
    #>
    [CmdletBinding()]
    param()

    try {
        # Get authentication for Azure DevOps
        try {
            $auth = Get-AzDOAuthenticationHeader
        } 
        catch {
            Write-Error "Failed to get Azure DevOps authentication. Please ensure you are logged in: $_"
            return
        }
        
        # Step 1: Get list of organizations
        Write-Host "Retrieving Azure DevOps organizations..." -ForegroundColor Yellow
        
        $organizations = Get-AzDOOrganizations -ReturnAsObject
        
        if (-not $organizations -or $organizations.Count -eq 0) {
            Write-Error "No Azure DevOps organizations found for the current user."
            return
        }
        
        Write-Verbose "Organizations retrieved:" 
        $organizations | ForEach-Object { Write-Verbose "- $($_.Name)" }
        
        # Step 2: Present organizations for selection
        $selectedOrg = Show-Menu -Title "Select Azure DevOps Organization" -Options $organizations -DisplayScript { param($org) return "$($org.Name)" }
        
        if (-not $selectedOrg) {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }
        
        # Step 3: Connect to the selected org without setting default project yet
        Write-Host "Connecting to organization '$($selectedOrg.Name)'..." -ForegroundColor Yellow
        Connect-AzDO -OrgName $selectedOrg.Name
        
        # Step 4: Get projects in the selected organization
        Write-Host "Retrieving projects from '$($selectedOrg.Name)'..." -ForegroundColor Yellow
        $projects = Get-VSTeamProject | Sort-Object -Property Name
        
        if (-not $projects -or $projects.Count -eq 0) {
            Write-Host "No projects found in the organization '$($selectedOrg.Name)'." -ForegroundColor Red
            return
        }
        
        # Step 5: Present projects for selection
        $selectedProject = Show-Menu -Title "Select Azure DevOps Project" -Options $projects -DisplayScript { param($proj) return "$($proj.Name) - $($proj.Description)" }
        
        if (-not $selectedProject) {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }
        
        # Step 6: Set default project
        Set-VSTeamDefaultProject -Project $selectedProject.Name
        
        # Step 7: Confirm connection
        $info = Get-VSTeamInfo
        
        Write-Host "`n✅ Successfully connected:" -ForegroundColor Green
        Write-Host "Organization : $($selectedOrg.Name)" -ForegroundColor Green
        Write-Host "Project      : $($selectedProject.Name)" -ForegroundColor Green
        Write-Host "URL          : $($info.Account)/$($selectedProject.Name)" -ForegroundColor Green
        
        # Optional: Ask about teams
        $showTeams = Read-Host "Would you like to see teams in this project? (y/n)"
        if ($showTeams -eq "y" -or $showTeams -eq "yes") {
            $teams = Get-VSTeam -ProjectName $selectedProject.Name | Select-Object Name, Description | Format-Table -AutoSize
            $teams
        }
        
        return $true
    }
    catch {
        Write-Error "An error occurred during setup: $_"
        return $false
    }
}
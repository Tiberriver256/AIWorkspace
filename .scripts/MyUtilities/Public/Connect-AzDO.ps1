function Connect-AzDO {
    <#
    .SYNOPSIS
        Connects to an Azure DevOps organization and optionally sets a default project.
    .DESCRIPTION
        This function obtains an Azure access token for Azure DevOps and connects to a specified organization.
        It can also set a default project for subsequent commands.
    .PARAMETER OrgName
        The name of the Azure DevOps organization to connect to.
    .PARAMETER ProjectName
        Optional. The name of the project to set as default.
    .EXAMPLE
        Connect-AzDO -OrgName "MyOrganization" -ProjectName "MyProject"
        Connects to the MyOrganization and sets MyProject as the default project.
    .EXAMPLE
        Connect-AzDO -OrgName "MyOrganization"
        Connects only to the MyOrganization without setting a default project.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OrgName,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectName
    )

    # VSTeam module check is moved to module import

    # Get authentication for Azure DevOps
    try {
        $auth = Get-AzDOAuthenticationHeader
        
        # Connect to Azure DevOps organization
        Set-VSTeamAccount -Account $OrgName -PersonalAccessToken $auth.Token -Version AzD
        Write-Host "Successfully connected to $OrgName organization" -ForegroundColor Green
        
        # Set default project if specified
        if ($ProjectName) {
            Set-VSTeamDefaultProject -Project $ProjectName
            Write-Host "Set $ProjectName as default project" -ForegroundColor Green
        }
        
        return $true
    } 
    catch {
        Write-Error "Failed to connect to Azure DevOps: $_"
        return $false
    }
}
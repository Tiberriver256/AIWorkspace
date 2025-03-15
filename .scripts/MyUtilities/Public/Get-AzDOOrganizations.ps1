function Get-AzDOOrganizations {
    <#
    .SYNOPSIS
        Lists all Azure DevOps organizations the current user has access to.

    .DESCRIPTION
        This function retrieves and lists all Azure DevOps organizations that the currently
        authenticated user has access to using Azure DevOps REST APIs.
        It can provide either basic information or detailed organization properties.

    .PARAMETER Detailed
        Optional. Switch to display detailed information about each organization including:
        - Organization Type
        - Status
        - Owner
        - Creation Details
        - Additional Properties

    .PARAMETER ReturnAsObject
        Optional. Returns the organizations as objects instead of formatting them for display.
        Useful when you need to process the results programmatically.

    .EXAMPLE
        Get-AzDOOrganizations
        Lists all Azure DevOps organizations with basic information (Name, ID, URL).

    .EXAMPLE
        Get-AzDOOrganizations -Detailed
        Lists all Azure DevOps organizations with detailed information including type, status, owner, etc.

    .EXAMPLE
        $orgs = Get-AzDOOrganizations -ReturnAsObject
        Stores organizations in the $orgs variable for further processing.

    .NOTES
        This function requires:
        - Az PowerShell module (for authentication)
        - Active Azure login with access to Azure DevOps
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Detailed,
        
        [Parameter(Mandatory = $false)]
        [switch]$ReturnAsObject
    )

    try {
        # Get authentication header
        $auth = Get-AzDOAuthenticationHeader
        
        # First, get user profile information to get the public alias
        Write-Verbose "Getting user profile information from Azure DevOps..."
        $profileResponse = Invoke-RestMethod -Uri "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=6.0" `
                                           -Headers $auth.Header
        
        if (-not $profileResponse.publicAlias) {
            throw "Could not retrieve user's public alias from Azure DevOps."
        }
        
        $publicAlias = $profileResponse.publicAlias
        
        # Get the list of organizations using the public alias
        Write-Verbose "Getting list of Azure DevOps organizations..."
        $orgsResponse = Invoke-RestMethod -Uri "https://app.vssps.visualstudio.com/_apis/accounts?memberId=$publicAlias&api-version=6.0" `
                                        -Headers $auth.Header
        
        # Process the organizations
        $organizations = foreach ($org in $orgsResponse.value) {
            if ($Detailed) {
                # Return detailed object with all available properties
                [PSCustomObject]@{
                    Name = $org.accountName
                    OrganizationId = $org.accountId
                    Url = $org.accountUri -replace ':443/', '/'
                    Type = $org.accountType
                    Status = $org.accountStatus
                    Owner = if ($org.owner) { $org.owner.displayName } else { "Unknown" }
                    OwnerEmail = if ($org.owner) { $org.owner.uniqueName } else { "Unknown" }
                    Created = if ($org.createdBy) { $org.createdBy.displayName } else { "Unknown" }
                    CreatedDate = if ($org.createdDate) { [DateTime]::Parse($org.createdDate) } else { "Unknown" }
                    LastAccessedDate = if ($org.lastAccessedDate) { [DateTime]::Parse($org.lastAccessedDate) } else { "Unknown" }
                    Properties = $org.properties
                }
            }
            else {
                # Return basic object with essential information
                [PSCustomObject]@{
                    Name = $org.accountName
                    OrganizationId = $org.accountId
                    Url = $org.accountUri -replace ':443/', '/'
                }
            }
        }
        
        # Return based on parameter
        if ($ReturnAsObject) {
            return $organizations
        }
        elseif ($Detailed) {
            $organizations | Format-List
        }
        else {
            $organizations | Format-Table -AutoSize
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
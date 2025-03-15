using namespace System.Web

function Get-BuildDefinitionsViaREST {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    try {
        # Get authentication header
        $auth = Get-AzDOAuthenticationHeader

        # Get current organization info from VSTeam
        $info = Get-VSTeamInfo
        if (-not $info -or -not $info.Account) {
            throw "No active Azure DevOps connection found. Use Connect-AzDO first."
        }

        # Clean up the organization name from the account info
        $orgName = $info.Account.TrimEnd('/')
        if ($orgName -match 'https://dev\.azure\.com/(.+)') {
            $orgName = $matches[1]
        }
        elseif ($orgName -match 'https://(.+)\.visualstudio\.com') {
            $orgName = $matches[1]
        }
        
        # Construct the API URL with proper escaping
        $orgUrl = "https://dev.azure.com/$orgName"
        $apiVersion = "7.1"
        
        # Use PowerShell's URI escaping
        $encodedProjectName = [uri]::EscapeDataString($ProjectName)
        
        # Get all definitions with expanded process information
        $apiUrl = "$orgUrl/$encodedProjectName/_apis/build/definitions?api-version=$apiVersion&queryOrder=lastModifiedDescending&includeAllProperties=true"

        Write-Verbose "Calling Azure DevOps API: $apiUrl"

        # Make the REST call for the first page
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $auth.Header -Method Get -ErrorAction Stop
        $definitions = @($response.value)
        
        # Handle pagination if there are more results
        while ($response.continuationToken) {
            $apiUrl = "$orgUrl/$encodedProjectName/_apis/build/definitions?api-version=$apiVersion&continuationToken=$($response.continuationToken)&includeAllProperties=true"
            Write-Verbose "Getting next page of results..."
            $response = Invoke-RestMethod -Uri $apiUrl -Headers $auth.Header -Method Get -ErrorAction Stop
            $definitions += $response.value
        }

        # Return all definitions
        return $definitions
    }
    catch {
        Write-Error "Failed to get build definitions via REST API: $($_.Exception.Message)"
        throw
    }
}
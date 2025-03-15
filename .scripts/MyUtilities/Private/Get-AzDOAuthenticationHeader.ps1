function Get-AzDOAuthenticationHeader {
    <#
    .SYNOPSIS
        Gets an authentication header for Azure DevOps API calls.
    .DESCRIPTION
        Attempts to get an authentication token in the following order:
        1. VSTeam token
        2. PAT token from environment variable
        3. Azure access token
    .OUTPUTS
        Returns a hashtable containing the authentication header and token
    .EXAMPLE
        $auth = Get-AzDOAuthenticationHeader
        $response = Invoke-RestMethod -Uri $url -Headers $auth.Header
    #>
    [CmdletBinding()]
    param()

    $token = $null
    $authHeader = $null
    
    # Try VSTeam token first
    try {
        $vsTeamToken = Get-VSTeamSecurityToken
        if ($vsTeamToken.Token) {
            Write-Verbose "Using VSTeam token"
            $token = $vsTeamToken.Token
            $authHeader = "Bearer $token"
        }
    }
    catch {
        Write-Verbose "VSTeam token not available: $_"
    }
    
    # Try PAT token next
    if (-not $token -and $env:AZURE_DEVOPS_PAT) {
        Write-Verbose "Using PAT token"
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:AZURE_DEVOPS_PAT)"))
        $authHeader = "Basic $base64AuthInfo"
        $token = $env:AZURE_DEVOPS_PAT
    }
    
    # Finally, try Az token
    if (-not $token) {
        Write-Verbose "Using Az token"
        $azToken = Get-AzAccessToken -ResourceUrl "499b84ac-1321-427f-aa17-267ca6975798" -AsSecureString
        
        # Convert SecureString to plain text
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($azToken.Token)
        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        
        $authHeader = "Bearer $token"
        Write-Verbose "Using Az token: $token"
    }
    
    if (-not $token) {
        throw "No valid authentication token found. Please set AZURE_DEVOPS_PAT environment variable or login with VSTeam/Az"
    }

    Write-Verbose "Using auth header type: $($authHeader.Split(' ')[0])"

    return @{
        Header = @{
            Authorization = $authHeader
            "Content-Type" = "application/json"
        }
        Token = $token
    }
} 
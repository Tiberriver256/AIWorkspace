function Show-Menu {
    <#
    .SYNOPSIS
        Displays an interactive menu and returns the selected item.
    .DESCRIPTION
        Creates a numbered menu from an array of options and lets the user select one.
        Supports custom display formatting through a script block.
    .PARAMETER Title
        The title to display above the menu.
    .PARAMETER Options
        Array of items to choose from.
    .PARAMETER DisplayScript
        Script block that determines how each option should be displayed.
    #>
    [CmdletBinding()]
    param (
        [string]$Title,
        [array]$Options,
        [scriptblock]$DisplayScript
    )
    
    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $displayText = & $DisplayScript $Options[$i]
        Write-Host "[$($i + 1)] $displayText"
    }
    
    Write-Host "[0] Cancel/Exit" -ForegroundColor Red
    Write-Host "=================================================" -ForegroundColor Cyan
    
    $selection = Read-Host "Enter selection"
    
    if ($selection -eq "0") {
        return $null
    }
    
    $index = [int]$selection - 1
    if ($index -ge 0 -and $index -lt $Options.Count) {
        return $Options[$index]
    }
    else {
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        return Show-Menu -Title $Title -Options $Options -DisplayScript $DisplayScript
    }
}
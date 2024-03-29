Import-Module PSGeoLocate.dll
$ErrorActionPreference = "Stop"    

function Import-Filters {

    Param(
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ })]
        [string]$FilterPath
    )

    try {
        $FilterData = Get-Content $FilterPath | Where-Object {$_ -notmatch "^#"}
        $Filters = [System.Collections.ArrayList]@()
  
        $FilterData | ForEach-Object {
            $Filter = [ScriptBlock]::Create($_)
            [void]$Filters.Add($Filter)
        }

        Write-Output $Filters

    }

    catch {
        Write-Host "Errors during filter import, please check your filter syntax" -ForegroundColor Yellow
        Write-Host $_.Exception.Message
    }
}

function Test-FirewallRulePresence {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName
    )

    try {
        if (!(Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)) {
            Write-Host "[+] Creating firewall rule called $RuleName"
            New-NetFirewallRule -DisplayName $RuleName -Enabled False -Profile Any -Direction Inbound -Action Block | Out-Null
        }
    }
    catch {
        Write-Error "Unable to create firewall rule, please ensure the windows firewall service is running and that you are running an elevated PowerShell session."
    }
}


function Start-GeoFence {
    [Cmdletbinding()]

    Param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ })]
        [string]$ConfigPath
    )

    Write-Host "[+] Loading PSGeoFence configuration"
    # Import configuration
    try {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Unable to parse configuration file JSON, please check that your JSON is valid"
    }

    Write-Host "[+] Importing filters"
    # Initial import of filters and ensuring named firewall rule is present. 
    $Filters = Import-Filters -FilterPath $Config.FilterPath
    Test-FirewallRulePresence -RuleName $Config.FirewallRuleName
    
    # Flag used to check whether the rule needs to be enabled. An empty Block rule will block Any/Any. 
    $EnableFirewall = $false

    # Set variables for calculated properties
    $ProcPath = @{Label = "ProcPath"; Expression = { (Get-Process -PID $_.OwningProcess | Select Path).Path } }
    $CC = @{Label = "CountryCode"; Expression = { (Get-GeoLocation -IPAddress $_.RemoteAddress -Path $Config.GeoLite2Path).CountryCode } }
    $CN = @{Label = "CountryName"; Expression = { (Get-GeoLocation -IPAddress $_.RemoteAddress -Path $Config.GeoLite2Path).CountryName } }

    # Counter used to determine when filters need to be updated
    $UpdateFiltersCounter = 0

    Write-Host "[+] Starting PSGeoFence"
    while ($true) {

        # Filters are updated every 10 loops
        $UpdateFiltersCounter ++

        if ($UpdateFiltersCounter -ge 10) {
            Write-Verbose "Updating filters"
            $Filters = Import-Filters -FilterPath $Config.FilterPath
            $UpdateFiltersCounter = 0
        }
  
        $Connections = Get-NetTCPConnection -AppliedSetting Internet | Where { $_.RemoteAddress -notmatch '^10\.|^172\.([0-2]|3[0-2])\.|^192\.168\.|127\.0\.0\.1|\[|\]|0\.0\.0\.0' } | Select Protocol, LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess, $CC, $CN, $ProcPath

        $FilterMatches = [System.Collections.ArrayList]@()
        $Filters | ForEach-Object {
            foreach ($Connection in $Connections | Where-Object $_.InvokeReturnAsIs()) {
                [void]$FilterMatches.Add($Connection)
            }
        }

        # $FilterMatches | Format-Table -AutoSize

        if ($FilterMatches.Count -ge 1) {

            foreach ($Match in $FilterMatches) {

                if ($Match.ProcPath) {
                    $Process = " using process $($Match.ProcPath)"
                } else {$Process = ""}

                Write-Host (Get-Date).toString() ": Blocking $($Match.RemoteAddress) ($($Match.CountryName)) for the connection to $($Match.LocalAddress):$($Match.LocalPort)$Process"

                $BlockedIPs = [array](Get-NetFirewallRule -DisplayName $Config.FirewallRuleName | Get-NetFirewallAddressFilter ).RemoteAddress

                if ($BlockedIPs -eq "Any") {
                    $EnableFirewall = $true
                }

                if ($Match.RemoteAddress -notin $BlockedIPs) {
                    $BlockedIPs += $Match.RemoteAddress
                    Set-NetFirewallRule -DisplayName $Config.FirewallRuleName -RemoteAddress $BlockedIPs
                }

                if ($EnableFirewall -eq $true) {
                    Set-NetFirewallRule -DisplayName $Config.FirewallRuleName -Enabled True
                    $EnableFirewall = $false
                }

                # Write-Host "Local Address $($Match.LocalAddress)", "Local Port $($Match.LocalPort)", "Remote Address $($Match.RemoteAddress)", "Remote Port $($Match.RemotePort)"
                Start-Process -FilePath $Config.CportsPath -ArgumentList "/close","$($Match.LocalAddress)","$($Match.LocalPort)","$($Match.RemoteAddress)","$($Match.RemotePort)" -Wait
            }
        }

        Start-Sleep -Milliseconds 500

    }
}

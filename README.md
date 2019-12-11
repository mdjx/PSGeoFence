# PSGeoFence

PSGeoFence is a PowerShell module that aims to provide very simple GeoFencing capability. 

## Limitations 

True GeoFencing prevents traffic from getting to the target in the first place, this module is reactive. That is, when an unwanted connection is detected, the offending IP is added to a firewall rule, and the connection is closed. Essentially, treat this as a *better than nothing* tool. 

Further, this will only detect TCP connections - services like HTTP/S, RDP, etc. UDP based services (SIP, DNS) will not be protected. 

Lastly, this will only prevent inbound connections. If you have a local service or application that attempts to establish an outbound connection to a blocked country/IP, it will be allowed. A feature to also block outbound connections may be added in a future release. 

## Preequisites 

1. A working [PSGeoLocate](https://github.com/davidski/PSGeoLocate) module install.
1. A copy of the [MaxMind GeoLite2 Country database](https://dev.maxmind.com/geoip/geoip2/geolite2/) in MaxMind DB format. 
1. A copy of the [CurrPorts](https://www.nirsoft.net/utils/cports.html) application. 

## Installation

Clone the repository and run `build.ps1 deploy`. 

Alternatively, copy the two files in `src` to a PowerShell module directory (eg. `C:\Program Files\WindowsPowerShell\Modules\PSGeoFence`) and rename `PSGeoFence.ps1` to `PSGeoFence.psm1`. 

## Configuration

You will need to create two additional files:
- A filter file that determines what connections get blocked
- A configuration file

### Filter file

This is simply a text file located anywhere on the system (the location will be referenced in the configuration file) that contains script blocks as strings. These strings will determine what connections are blocked. Each line is a filter and the syntax is identical to `Where-Object` script blocks. 

Available parameters are
- LocalAddress
- LocalPort
- RemoteAddress
- RemotePort
- State
- PID (Process ID)
- CountryCode (AU/NZ/US/FR/etc)
- CountryName (Australia, New Zealand, etc)
- ProcPath (Process Path)


**Example File**

```powershell
# Block inbound HTTPS connections from countries other than Australia
{($_.LocalPort -eq 443) -and ($_.CountryCode -ne "AU")}

# Block any connections to Service.exe from countries other than Australia and New Zealand
{($_.CountryCode -match "AU|NZ") -and ($_.ProcPath -match "Service.exe")}
```

Comments can be used in the file to describe the purpose of each filter. 

### Configuration file

The configuration file is a JSON file that points to various prerequisites and configures options such as the name of the firewall rule.

**Example File**

```json
{
    "CportsPath": "C:\\Tools\\PSGeoFence\\bin\\cports.exe",
    "GeoLite2Path": "C:\\Tools\\PSGeoFence\\db\\GeoLite2-Country.mmdb",
    "FilterPath":  "C:\\Tools\\PSGeoFence\\filters\\filters.cfg",
    "FirewallRuleName" : "00-PSGeoFence IP Blocks"
}
```

## Running PSGeoFence

```powershell
Import-Module PSGeoFence
Start-GeoFence -ConfigPath C:\Tools\PSGeoFence\config\config.json
```

`Start-GeoFence` will import the configuration data and start a loop continually checks for connections matching the supplied filters. The remote IP of these connections is added to the firewall rule, and the connection is terminated. 
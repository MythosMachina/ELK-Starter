Param(
    [string]$AgentVersion = $env:AGENT_VERSION,
    [string]$FleetUrl = $env:FLEET_URL,
    [Parameter(Mandatory=$true)] [string]$EnrollmentToken
)

if (-not $AgentVersion) {
    if ($env:STACK_VERSION) {
        $AgentVersion = $env:STACK_VERSION
    } else {
        $AgentVersion = '8.16.3'
    }
}

if (-not $FleetUrl) {
    $FleetUrl = 'https://localhost:8220'
}

$Zip = "elastic-agent-$AgentVersion-windows-x86_64.zip"
$DownloadUrl = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$Zip"

Invoke-WebRequest -Uri $DownloadUrl -OutFile $Zip
Expand-Archive -Path $Zip -DestinationPath . -Force
Set-Location "elastic-agent-$AgentVersion-windows-x86_64"

# Install and enroll the agent non-interactively
Start-Process .\elastic-agent.exe -ArgumentList @(
    'install',
    '--url', $FleetUrl,
    '--enrollment-token', $EnrollmentToken,
    '--certificate-authorities', '..\certs\ca.crt',
    '-b'
) -Wait -NoNewWindow

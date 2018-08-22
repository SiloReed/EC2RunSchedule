<#
.SYNOPSIS
    Use this script to unit test cmdlets in the EC2RunSchedule module
.DESCRIPTION
    Use this script to unit test cmdlets in the EC2RunSchedule module. 
.EXAMPLE
    .\UnitTest.ps1
#>
[CmdletBinding()]

$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir "EC2RunSchedule.psd1")

$FilterPath = Join-Path $ScriptDir 'RunScheduleFilter.json'

$title = "Choose a command to execute"
$commands = @()

$commands += "Get-EC2RunSchedule -FilterPath $FilterPath -Verbose"
$commands += "Get-EC2RunSchedule -FilterPath $FilterPath"
$commands += "Get-EC2RunSchedule -Name 'AWUE1ADDC*' -Region 'us-east-1'"

$commands += "Set-EC2RunSchedule -FilterPath $FilterPath -Verbose"
$commands += "Set-EC2RunSchedule -Name 'AWUE1ADDC01' -Region 'us-east-1' -Verbose -Enabled -RunHours 10 -RunDays 1,2,3,4,5 -StartHourUTC 13 -AutoStart"
$commands += "Set-EC2RunSchedule -Name 'AWUE1ADDC*' -Region 'us-east-1' -Verbose -Enabled -RunHours 13 -RunDays Monday,Wednesday,Friday -StartHourUTC 13 -AutoStart"
$commands += "Set-EC2RunSchedule -Name 'AWUE1ADDC*' -Region 'us-east-1' -Verbose -RunHours 13 -RunDays Monday,Wednesday,Friday -StartHourUTC 13 -AutoStart"
$commands += "Set-EC2RunSchedule -Name 'AWUE1ADDC*' -Region 'us-east-1' -Verbose -Enabled"
$commands += "Set-EC2RunSchedule -Name 'AWUE1ADDC*' -Region 'us-east-1' -Verbose -Enabled:`$false"

$commands += "Remove-EC2RunSchedule -FilterPath $FilterPath -Verbose"
$commands += "Remove-EC2RunSchedule -Name 'AWUE1ADDC*' -Region 'us-east-1' -Verbose"
$commands += "Remove-EC2RunSchedule -Name 'AWUE1ADDC01' -Region 'us-east-1' -Verbose"
$commands += "Remove-EC2RunSchedule -Name 'AWUW1ADDC01' -Region 'us-west-1' -Verbose"

$c = $commands | Out-GridView -Title $title -OutputMode Single
Write-Output "Executing: $c"
Invoke-Expression $c

Remove-Module EC2RunSchedule
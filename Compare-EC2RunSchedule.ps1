#region Comment Based Help
<#
.SYNOPSIS
    Starts or stops Amazon EC2 instances by comparing their RunSchedule
    to the current time in UTC.
.DESCRIPTION
    Starts or stops Amazon EC2 instances by comparing their RunSchedule
    to the current time in UTC. 
.NOTES
    Author: Jeff Reed
    Name: Compare-EC2RunSchedule.ps1
    Created: 2018-08-20
    Email: siloreed@hotmail.com

    The script has no command line parameters. Instead, all script variables
    that would normally be passed as parameters are instead read from a 
    JSON file in the same directory as the script. This design makes it 
    much easier to debug the script and configure a scheduled task for 
    the script. 
#>
#endregion Comment Based Help

#requires -version 5
#requires -modules EC2RunSchedule, AWSPowerShell

[CmdletBinding()]
param()

#region Functions

#region Function Out-Log
function Out-Log {
    <#  
    .SYNOPSIS
        Writes output to the log file.
    .DESCRIPTION
        Writes output the Host and appends output to the log file with date/timestamp
    .PARAMETER Message
        The string that will be output to the log file
    .PARAMETER Level
        One of: "Info", "Warn", "Error", "Verbose"
    .NOTES    
        Requires that the $Script:log variable be set by the caller
    .EXAMPLE
        Out-Log "Test to write to log"
    .EXAMPLE
        Out-Log -Message "Test to write to log" -Level "Info"
    #>

    [CmdletBinding()]
    param (
        [Parameter (
            Position=0, 
            Mandatory=$true,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [string] $Message,
        [Parameter (
            Position=1, 
            Mandatory=$false,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [ValidateSet("Info", "Warn", "Error", "Verbose")]
        [string] $Level = "Info"
    )
	
    $ts = $(Get-Date -format "s")
    $s = ("{0}`t{1}`t{2}" -f $ts, $Level, $Message)
    if ($Level -eq "Verbose") {
        # Only log and output if script is called with -Verbose common parameter
        if ( $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue ) {
            Write-Output $s
            Write-Output $s | Out-File -FilePath $script:log -Encoding utf8 -Append
        }
    } 
    else {
        Write-Output $s
        Write-Output $s | Out-File -FilePath $script:log -Encoding utf8 -Append
    }
}
#endregion Function Out-Log

#region Function Send-ErrorMessage
function Send-ErrorMessage {
    <#  
    .SYNOPSIS
        Sends an email containing the error message
    .DESCRIPTION
        Sends an email containing the error message
    .NOTES    
        Requires that the $script:To, $script:SmtpServer, and $script:Domain variables be set by the calling script
    .EXAMPLE
        Send-ErrorMessage "Some error message to email"
    .PARAMETER errorMsg
        The error message that will be emailed
    #>

    [CmdletBinding()]
	param ( 
        [Parameter(	Position=0, 
            Mandatory=$true,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False) ]
		[string] $Message
	)
	
	$m = ("Sending email message to {0} via SMTP server {1}. Message: {2}" -f $script:To, $script:SMTPServer, $Message)
    Out-Log -Level Error -Message $m
	try {
        $subject = $($scriptName + " script FAILED")
    	$body = @"
<font Face="Calibri">$scriptName failed!<br>Script Server: $env:Computername<br>Error Message: $Message</Font>
"@
        $MailMessage = @{
            To = $script:To 
            Subject = $subject 
            From = "$env:Computername@$script:Domain"
            Body = $body 
            SmtpServer = $script:SMTPServer
            BodyAsHtml = $True			
            Encoding = ([System.Text.Encoding]::UTF8) 
            Priority = "High"		
        }     
        Send-MailMessage @MailMessage -ErrorAction Stop
    } catch {
        $ErrorMessage = $_.Exception.Message
        Out-Log -Level Error -Message "System.Net.Mail.SmtpClient:SmtpClient: $ErrorMessage"
    }
}
#endregion Function Send-ErrorMessage

#region Function Read-Variables
function Read-Variables {
    <#
    .SYNOPSIS
        Reads the contents of a JSON file in the same directory as the script in order to set 
        script wide variables.   
    .DESCRIPTION
        Reads the contents of a JSON file in the same directory as the script in order to set 
        script wide variables. The JSON filename must be <script_basename>.json
    #>

    # Define the variables required by the script that must be set in the JSON document
    $RequiredVars = @("FilterPath", "SMTPServer", "To", "Domain")

    # Loop through vars and remove them if they were previously set.
    foreach ($v in $RequiredVars) {
        if (Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue) {
            Remove-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue
        }
    }

    $jsonFile = Join-Path $scriptDir ($scriptBaseName + ".json")
    if (-not (Test-Path $jsonFile) ) {
        $m = ("{0} not found." -f $jsonFile)
        Send-ErrorMessage -Message $m
        Throw $m
    }
    $json = Get-Content $jsonFile | ConvertFrom-Json
    foreach ($var in $json.Variables) {
        try {
            New-Variable -Name $var.Name -Value $var.Value -Scope Script -ErrorAction Stop
        }
        catch {
            Set-Variable -Name $var.Name -Value $var.Value -Scope Script
        }
    }

    # Check that all required vars are set
    foreach ($v in $RequiredVars) {
        if ($Null -eq (Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue) ) {
            $m = ("The variable '{0}' is not defined in {1}." -f $v, $jsonFile)
            Send-ErrorMessage -Message $m
            Throw $m          
        }
    }
}
#endregion Function Read-Variables

#region Function Compare-Instance
function Compare-Instance 
{
    <#
    .SYNOPSIS
        Compares the RunSchedule tag to the current date and time. 
    .DESCRIPTION
        Compares the RunSchedule tag to the current date and time. 
        This is used to determine if the instance is considered
        "in schedule" or out of schedule. The instance will
        be started or Stopped based to the RunSchedule and 
        current date and time.
    .PARAMETER Instance
        One or more instance objects.
    #>

    param(  
    [Parameter(
        Position=0, 
        Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)
    ]
    [Amazon.EC2.Model.Instance[]]$Instance
    ) 
    begin {
        # Executes once at the start of the pipeline
        $CurrentTimeUTC = (Get-Date).ToUniversalTime()
        [int] $CurrentDayUTC = $CurrentTimeUTC.DayOfWeek.ToString("d")
        [int] $CurrentHourUTC = $CurrentTimeUTC.Hour
        $CurrentHoursSinceSun = ($CurrentDayUTC * 24) + $CurrentHourUTC
    }

    process {
        # Executes for each pipeline object
        foreach ($i in $Instance) {
            
            # Get the tags on the instance
            $InstanceName = ($i.Tag | Where-Object {$_.Key -eq "Name"}).Value
            Write-Verbose ("Checking Instance {0} " -f $InstanceName)
            $TagRSValue = ($i.Tag | Where-Object {$_.Key -eq "$scriptTag"}).Value

            # Check if the RunSchedule tag does not exists
            if ($Null -eq $TagRSValue) {
                # The tag doesn't exist
                Out-Log -Level Info -Message ("The {0} tag is not set for the instance {1}" -f $scriptTag, $InstanceName)
                Continue
            }
            else {
                # The tag exists
                try {
                    $RunSchedule = $TagRSValue | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    $command = $_.InvocationInfo.MyCommand.Name        
                    $ex = $_.Exception
                    Out-Log -Level Warn -Message ("{0} failed: {1}" -f $command, $ex.Message)
                    Continue
                }
            }
        
           # If the schedule is disable log it
            if (-not ($RunSchedule.Enabled) ) {
                Out-Log -Level Info -Message ("{0} is not enabled for {1}. Skipping." -f $scriptTag, $InstanceName)
                Continue
            }
            # Enabled property must be true and three schedule tags must have values else instance is skipped
            if ( ($RunSchedule.Enabled) -and ($Null -ne $RunSchedule.StartHourUTC) -and ($Null -ne $RunSchedule.RunHours) -and ($Null -ne $RunSchedule.RunDays)) 
            {
                try 
                {
                    $StartHour = [int] $RunSchedule.StartHourUTC
                } 
                catch 
                {
                    Out-Log -Level Warn -Message ("Conversion of StartHourUTC tag failed for {0}. The error message was: {2}" -f $InstanceName, $_.Exception.Message)
                    Continue
                }

                try 
                {
                    $RunningHours = [int] $RunSchedule.RunHours
                } 
                catch 
                {
                    Out-Log -Level Warn -Message ("Conversion of RunHours tag failed for {0}. The error message was: {2}" -f $InstanceName, $_.Exception.Message)
                    Continue
                }

                try 
                {
                    # Make an array of the runnable days that the instance is allowed to run. Split the string on any of these characters: , ; tab space
                    $RunnableDays = [System.DayOfWeek[]] $RunSchedule.RunDays
                    # Sort the RunDays because the script author has OCD
                    $RunnableDays = $RunnableDays | Sort-Object
                    # Make a string of the days for single line display
                    $strDays = [string]::Join(",", $RunnableDays)
                } 
                catch 
                {
                    Out-Log -Level Warn -Message ("Conversion of RunDays tag failed for {0}. The error message was: {2}" -f $InstanceName, $_.Exception.Message)
                    Continue
                }

                if ( ($StartHour -lt 0) -or ($StartHour -gt 23) ) 
                {
                    Out-Log -Level Warn -Message ("StartHour tag is: {0} for instance {1}. Valid values are 0-23 inclusive. The error message was: {2}." + $StartHour, $InstanceName, $_.Exception.Message)
                    Continue
                }

                if ( ($RunningHours -lt 0) -or ($RunningHours -gt 24) ) 
                {
                    Out-Log -Level Warn -Message ("RunHours tag is: {0} for instance {1}. Valid values are 0-24 inclusive. The error message was: {2}." + $StartHour, $InstanceName, $_.Exception.Message)
                    Continue
                }
                $IsInSchedule = $False
                # Loop through the $RunnableDays
                foreach ($rd in $RunnableDays)
                {
                    $intDay = $rd.value__
                    # For this particular day this is the number of hours since Sunday at midnight that the StartHour occurs
                    $ThisDayStart = ($intDay * 24) + $StartHour
                    # For this particular day this is the number of hours since Sunday at midnight that the schedule end (i.e. StartHour + RunningHours)
                    $ThisDayEnd = $ThisDayStart + $RunningHours
                    # This checks if the current hour is within the schedule for this particular day
                    if (($CurrentHoursSinceSun -ge $ThisDayStart) -and ($CurrentHoursSinceSun -lt $ThisDayEnd))
                    {
                        $IsInSchedule = $True
                        # Break out of the foreach loop since the Instance is "in schedule"
                        Break
                    }
                    # This is the case where we wrap around on Sunday at midnight which is both hour 0 and hour 168
                    if ($ThisDayEnd -gt 167)
                    {
                        # Get hours after 168
                        $HoursAfterMidnightSun = $ThisDayEnd - 168
                        if ($CurrentHoursSinceSun -lt $HoursAfterMidnightSun) 
                        {
                            $IsInSchedule = $True
                        }
                    }
                }

                # Get Instance State
                $state = $i.State.Name

                if ( $IsInSchedule ) {
                    if  ( $state -ine "running") {
                        # Check if AutoStart tag is True
                        if ($RunSchedule.AutoStart) {
                            $m = ("Starting instance {0}. StartHourUTC is {1}. RunHours is {2}. RunDays is: [{3}]" -f $InstanceName, $RunSchedule.StartHourUTC, $RunSchedule.RunHours, $strDays)
                            Out-Log -Level Info -Message $m
                            Set-InstanceState -Action "Start" -Instance $i
                        }
                        else {
                            $m =  ("{0} is in schedule but AutoStart is false. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $InstanceName, $RunSchedule.StartHourUTC, $RunSchedule.RunHours, $strDays, $state)
                            Out-Log -Level Verbose -Message $m
                        }
                    } else {
                        $m = ("{0} should be running. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $InstanceName, $RunSchedule.StartHourUTC, $RunSchedule.RunHours, $strDays, $state)
                        Out-Log -Level Verbose -Message $m
                    }
                } else {
                    if  ( ($state -ieq "running") -or ($state -ieq "pending") ) {
                        $m = ("Stopping {0}. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $InstanceName, $RunSchedule.StartHourUTC, $RunSchedule.RunHours, $strDays, $state)
                        Out-Log -Level Info -Message $m
                        Set-InstanceState -Action "Stop" -Instance $i
                    } else {
                        $m = ("{0} should be stopped. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $InstanceName, $RunSchedule.StartHourUTC, $RunSchedule.RunHours, $strDays, $state)
                        Out-Log -Level Verbose -Message $m
                    }
                }
            }
        }
    }
    end {
        Out-Log -Level Verbose -Message "Finished processing the pipeline"
    }

} 
#endregion Function Compare-Instance

#region Function Set-InstanceState
function Set-InstanceState
{
    <#
    .SYNOPSIS
        Starts or Stops a instance.
    .DESCRIPTION
        Starts or Stops a instance.
    .PARAMETER Action
        The action that will be performed on the instance. 
        Either 'Start' or 'Stop'
    .PARAMETER Instance
        The name tag of the EC2 instance 
    .PARAMETER Tag
        The current RunSchedule tag
    #>
    Param
    (
        [Parameter(Mandatory=$true,
                    ValueFromPipelineByPropertyName=$false,
                    HelpMessage="The action that will be performed on the instance.",
                    Position=0)]
        [ValidateSet("Start","Stop")]
        [string] $Action,
 
        [Parameter(Mandatory=$true,
                    ValueFromPipelineByPropertyName=$false,
                    HelpMessage="The instance object.",
                    Position=1)]
        [Amazon.EC2.Model.Instance] $Instance

    )

    # Get the tags on the instance
    $InstanceName = ($i.Tag | Where-Object {$_.Key -eq "Name"}).Value
    Write-Verbose ("Checking Instance {0} " -f $InstanceName)
    $TagRSValue = ($i.Tag | Where-Object {$_.Key -eq "$scriptTag"}).Value
    # Remove the last character of the instance's AvailabilityZone to determine its region
    $Region = $Instance.Placement.AvailabilityZone.Substring(0, $i.Placement.AvailabilityZone.Length-1)

    try {
        $RunSchedule = $TagRSValue | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        Out-Log -Level Warn -Message  ("{0} failed: {1}" -f $command, $ex.Message)
        break
    }

    if ($Action -eq "Stop") {
        try {
            Stop-EC2Instance -InstanceId $Instance.InstanceId -Region $Region | Out-Null
        }
        catch {
            $command = $_.InvocationInfo.MyCommand.Name        
            $ex = $_.Exception
            Out-Log -Level Warn -Message  ("{0} failed: {1}" -f $command, $ex.Message)
            break
        }

        Set-Status -Action Stopped -Status ([ref] $RunSchedule.Status)
    } 
    else {
        try {
            Start-EC2Instance -InstanceId $Instance.InstanceId -Region $Region | Out-Null
        }
        catch {
            $command = $_.InvocationInfo.MyCommand.Name        
            $ex = $_.Exception
            Out-Log -Level Warn -Message  ("{0} failed: {1}" -f $command, $ex.Message)
            break
        }
        Set-Status -Action Started -Status ([ref] $RunSchedule.Status)
    }

    # Convert the PSCustomObject to JSON minified
    $json = $RunSchedule | ConvertTo-Json -Compress
    try {
        New-EC2Tag -Resource $Instance.InstanceId -Region $Region -Tag @{ Key=$scriptTag; Value = $json}
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        Out-Log -Level Warn -Message  ("{0} failed: {1}" -f $command, $ex.Message)
        break
    }

} 
#endregion Function Set-InstanceState

#endregion Functions

#region Script Body

# Enable verbose output
$VerbosePreference = "Continue"

# This is the tag that this script will get from the instance
$scriptTag = "RunSchedule"

# Get this script
$ThisScript = $Script:MyInvocation.MyCommand
# Get the directory of this script
$scriptDir = Split-Path $ThisScript.Path -Parent
# Get the script file
$scriptFile = Get-Item $ThisScript.Path
# Get the name of this script
$scriptName = $scriptFile.Name
# Get the name of the script less the extension
$scriptBaseName = $scriptFile.BaseName

# Define folder where log files are written
$logDir = Join-Path $scriptDir "Logs"

if ((Test-Path $logDir) -eq $FALSE) {
    New-Item $logDir -type directory | Out-Null
}

# The new logfile will be created every day
$logdate = get-date -format "yyyy-MM-dd"
$log = Join-Path $logDir ($scriptBaseName +"_" + $logdate + ".log")
Write-Output "Log file: $log"

# Use the first profile to make the connection
$profileName = (Get-AWSCredential -ListProfileDetail | Select-Object -First 1).ProfileName
$AccessKey = (Get-AWSCredential -ProfileName $profileName).GetCredentials().AccessKey
Out-Log -Level Info -Message ("{0} script started on {1} using IAM Access Key {2}" -f $scriptName, $env:COMPUTERNAME, $AccessKey)

# Read the script variables from a json file in the same directory as the script
Read-Variables
   
if (-not (Test-Path $FilterPath) ) {
        $m = ("FilterPath '{0}' is invalid." -f $FilterPath)
        Send-ErrorMessage -Message $m
        Throw $m    
} 
else {
    Find-Instances -FilterPath $FilterPath -Action Get | Compare-Instance
}   
   
Out-Log -Level Info -Message ("{0} script completed on {1} using IAM Access Key {2}" -f $scriptName, $env:COMPUTERNAME, $AccessKey)
#endregion Script Body
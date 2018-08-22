#Requires -Modules AWSPowerShell
#Requires -Version 5

<#
.SYNOPSIS
   This PowerShell module contains functions related to manipuliating the RunSchedule tag on Amazon EC2 instances.
.DESCRIPTION
    This PowerShell module contains functions related to manipuliating the RunSchedule tag on Amazon EC2 instances.
.NOTES
    Author: Jeff Reed
    Name: EC2RunSchedule.psm1
    Created: 2018-08-20
    Email: siloreed@hotmail.com
#>

# Start Module Functions
function Find-Instances {
    <#  
    .SYNOPSIS
        Returns an array of instances based on JSON input file or instance name
    .DESCRIPTION
        Returns an array of instances based on JSON input file or instance name
    .PARAMETER Name
        The name of the instance.
    .PARAMETER Region
        The region of the instance.
    .PARAMETER Tag
        If specified the tag will be updated on the instance.
        If specified but a null string, the tag will be removed.
        If not specified no action is taken on the tag. 
    .PARAMETER FilterPath
        An optional JSON file that specifies a filter of instances, so that all instances in a subscription are not examined.
    .PARAMETER Action
        The action to the perfom the instances, either Get, Set, Enable, Disable, or Remove.
    .EXAMPLE
        Find-Instances -FilterPath "C:\Temp\instance-Filter.json"
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]
    Param (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the instance."
        )]
        [string] $Name,

        [Parameter(
            Position=1,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The region of the instance."
        )]
        [string] $Region,

        [Parameter(
            Position=0,
            ParameterSetName='JSONFile',        
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="JSON file that specifies a filter of instances."
        )]
        [string] $FilterPath,
        [Parameter(
            Position=1,
            ParameterSetName='JSONFile',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The action to perform on the RunSchedule tag, either Get, Set, Enable, Disable, or Remove."
        )]
        [Parameter(
            Position=2,
            ParameterSetName='CmdLine',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The action to perform on the RunSchedule tag, either Get, Set, Enable, Disable, or Remove."
        )]
        [ValidateSet("Get", "Set", "Enable", "Disable", "Remove")] 
        [string] $Action,

        [Parameter(
            Position=3,
            ParameterSetName='CmdLine',        
            Mandatory=$False,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The new tag value."
        )]
        [string] $Tag
    )

    if ($PSCmdlet.ParameterSetName -eq "CmdLine") {

        $filter = @(New-Object Amazon.EC2.Model.Filter -Property @{Name = "tag:Name"; Values = $Name})
        $filteredInstances = (Get-EC2Instance -Filter $filter -Region $Region).Instances
        if ($Action -ne "Get") {
            foreach ($instance in $filteredInstances) {
                # Get the RunSchedule tag value
                $TagRSValue = ($instance.Tags | Where-Object {$_.Key -eq $script:TagRS}).Value
                # Get the instance name
                $InstanceName = ($instance.Tags | Where-Object {$_.Key -eq "Name"}).Value    
                switch ($Action) {
                    "Set" {
                        if ($Tag.Length -gt 0) {
                            Set-Tag -InstanceId $instance.InstanceId -Region $Region -Tag $Tag
                        }
                    }
                    "Remove" {
                        Set-Tag -InstanceId $instance.InstanceId -Region $Region -Tag ""
                    }
                    "Enable" {
                        # Check if the RunSchedule tag does not exist
                        if ($TagRSValue -eq $Null) {
                            # The tag doesn't exist
                            Write-Warning ("Can't enable! The {0} tag is not set for the instance {1}. Set the tag first." -f $script:TagRS, $InstanceName)
                            return
                        }
                        else {
                            $o = $TagRSValue | ConvertFrom-Json
                            # Only update the tag if enabled was disabled
                            if (-not ($o.Enabled) ) {
                                $o.Enabled = $true
                                Set-Status -Action Enabled -Status ([ref] $o.Status)
                                $Tag = $o | ConvertTo-Json -Compress
                                Set-Tag -InstanceId $instance.InstanceId -Region $Region -Tag $Tag
                            }
                        }
                    }
                    "Disable" {
                        # Check if the RunSchedule tag does not exist
                        if ($TagRSValue -eq $Null) {
                            # The tag doesn't exist
                            Write-Warning ("Can't enable! The {0} tag is not set for the instance {1}. Set the tag first." -f $script:TagRS, $InstanceName)
                            return
                        }
                        else {
                            $o = $TagRSValue | ConvertFrom-Json
                            # Only update the tag if enabled was enabled
                            if ($o.Enabled) {
                                $o.Enabled = $false
                                Set-Status -Action Disabled -Status ([ref] $o.Status)
                                $Tag = $o | ConvertTo-Json -Compress
                                Set-Tag -InstanceId $instance.InstanceId -Region $Region -Tag $Tag
                            }
                        }
                    }
                    default {}
                }
            }
        }
    }
    else {
        if ($FilterPath.Length -gt 0) {
            if (Test-Path $FilterPath) {
                # Import the JSON document
                try {
                    $instancesJSON = Get-Content -Path $FilterPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    $command = $_.InvocationInfo.MyCommand.Name        
                    $ex = $_.Exception
                    Throw  ("{0} failed: {1}" -f $command, $ex.Message)
                }
                # Create a filtered list of instances only if we have valid JSON data imported from the filter file
                if ($instancesJSON -ne $null) {
                    # Reset the filtered list of instances to an empty array
                    $filteredInstances = @()
                    foreach ($r in $instancesJSON.regions) {
                        foreach ($i in $r.instances) {
                            $json = ""
                            # Get the RunSchedule JSON data if it exists for this instance node
                            if ([bool] ($i.PSObject.Properties.Name -match "RunSchedule") ) {
                                # The Status data is irrelevant in the filter file, so update the values in case the Action is Set
                                Set-Status -Action Set -Status ([ref] $i.RunSchedule.Status)
                                # Convert the object back to JSON
                                $json = $i.RunSchedule | ConvertTo-Json -Compress
                            }

                            $filter = @(New-Object Amazon.EC2.Model.Filter -Property @{Name = "tag:Name"; Values = $i.Name})
                            $instances = (Get-EC2Instance -Filter $filter -Region $r.name).Instances
                            foreach ($instance in $instances) {
                                # Set the RunSchedule as it's set in the JSON file and the function was called with Action=Set
                                if ( ($json -ne $null) -and ($Action -eq "Set") ) {
                                    Set-Tag -InstanceId $instance.InstanceId -Region $r.Name -Tag $json
                                }
                                # Remove the RunSchedule tag as the fuction was called with Action=Remove
                                if ($Action -eq "Remove") {
                                    Set-Tag -InstanceId $instance.InstanceId -Region $r.Name -Tag ""
                                }
                                $filteredInstances += $instances
                            }
                        }
                    }
                }
            }
        }
    }

    return $filteredInstances
} # End function Find-Instances

function Set-Tag {
    <#  
    .SYNOPSIS
        Sets the tag on a instance
    .DESCRIPTION
        Sets the tag on a instance
    .PARAMETER InstanceId
        An instance ID
    .PARAMETER Tag
        If specified the tag will be updated on the instance.
        If specified but a null string, the tag will be removed.
        If not specified no action is taken on the tag.
    .EXAMPLE
        Set-Tag -InstanceId $InstanceId
    #>

    [CmdletBinding()]
    param (
        [Parameter(
            Position=0,
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The instance ID."
        )]
        [string] $InstanceId,

        [Parameter(
            Position=1,
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The region of the instance."
        )]
        [string] $Region,    

        [Parameter(
            Position=2,
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Update the tag with a new value. If null the tag will be removed."
        )]
        [string] $Tag    
    )

    # Determine if the tag should be removed or set to a new value
    $Remove = $False
    if (-not ($PSBoundParameters.ContainsKey("Tag") ) ) {
        Write-Debug "No tag was set"
        return
    }
    else {
        Write-Debug "Tag exists"
        if ($Tag.Length -gt 0) {
            Write-Debug "Tag is $Tag"
            $Remove = $False
        }
        else {
            $Remove = $True
        }
    }

    # Get the tags on the instance
    $filter = @()
    $filter += New-Object Amazon.EC2.Model.Filter -Property @{Name = "key"; Values = $script:TagRS}
    $filter += New-Object Amazon.EC2.Model.Filter -Property @{Name = "resource-id"; Values = $InstanceId}
    $filter += New-Object Amazon.EC2.Model.Filter -Property @{Name = "resource-type"; Values = "instance"}
    $TagRSValue = Get-EC2Tag -Filter $filter -Region $Region

    if ($Remove) {
        if ($TagRSValue -eq $Null) {
            Write-Verbose ("Nothing to do: The {0} tag is not set for the instance {1}" -f $script:TagRS, $InstanceName)
            return
        }
        else {
            # The tag exists so remove it
            Remove-EC2Tag -Resource $InstanceId -Region $Region -Tag @{ Key=$script:TagRS } -Force
            return
        }
    }
    else {
        # Add (if it doesn't exist) or update (if it already exists) the tag 
        New-EC2Tag -Resource $InstanceId -Region $Region -Tag @{ Key=$script:TagRS; Value = $Tag }
    }
} # End function Set-Tag

function Get-EC2RunSchedule {
    <#
    .SYNOPSIS
        Gets the run schedule for a given Amazon EC2 instance.
    .DESCRIPTION
        Gets the run schedule for a given Amazon EC2 instance.
    .PARAMETER Name
        The name of the instance.
    .PARAMETER Region
        The region of the instance.
    .PARAMETER FilterPath
        A JSON file that specifies a filter of instances, so that all instances are not examined.
    .EXAMPLE
        Get-EC2RunSchedule -Name "AWUE1*" -Region "us-east-1"
    .EXAMPLE
        Get-EC2RunSchedule -FilterPath ".\RunScheduleFilter.json"
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]

    Param
    (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the instance."
        )]
        [string] $Name,

        [Parameter(
            Position=1,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The region of the instance."
        )]
        [string] $Region,

        [Parameter(
            Position=0,
            ParameterSetName='JSONFile',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="A JSON file that specifies a list of instances."
        )]
        [string] $FilterPath
    )

    # Determine which parameter set script was called with
    if ($PSCmdlet.ParameterSetName -eq "CmdLine") {
        $Instances = Find-Instances -Name $Name -Region $Region -Action Get
        # Make sure instances were found else display a warning message
        if ($Instances -eq $Null) {
            Throw ("No instances were found where the resource group name was '{0}' and the instance name was '{1}'" -f $ResourceGroupName, $Name)
        }
    }
    else {
        if (-not (Test-Path $FilterPath) ) {
            Throw ("{0} is not a valid path." -f $FilterPath)
        }
        else {
            # Find instances in the subscription that match the JSON in the filter file.
            $Instances = Find-Instances -FilterPath $FilterPath -Action Get
        }
        # Make sure instances were found else display a warning message
        if ($Instances -eq $Null) {
            Write-Debug ("No instances were found. Check the JSON document '{0}'" -f $FilterPath)
            return
        }
        
    }
    # Create an empty array for the output
    $InstanceSchedules = @()

    foreach ($instance in $Instances) {

        # Get the RunSchedule tag value
        $TagRSValue = ($instance.Tags | Where-Object {$_.Key -eq $script:TagRS}).Value
        # Get the instance name
        $InstanceName = ($instance.Tags | Where-Object {$_.Key -eq "Name"}).Value    

        # Check if the RunSchedule tag does not exist
        if ( $TagRSValue -eq $Null) {
            # The tag doesn't exist
            $object = New-Object psobject -Property @{
                Name = $InstanceName
                Enabled = $Null
                AutoStart = $Null
                RunDays = $Null
                StartHourUTC = $Null
                StartHourLocal = $Null
                RunHours = $Null
                Schedule = $Null
            }
            $InstanceSchedules += $object

        }
        else {
            # The tag exists so output the tag info
            $o =  $TagRSValue | ConvertFrom-Json
            # RunDays are special because they are stored as in array of ints. Cast them back to an array of System.DayOfWeek
            $RunDays = [System.DayOfWeek[]] $o.RunDays
            # Sort the RunDays because the script author has OCD
            $RunDays = $RunDays | Sort-Object
            # Get the name of the local time zone
            $tzName = (Get-WmiObject win32_timezone).StandardName
            # Get the current offset of local time from UTC time - this works for standard and daylight savings time.
            $OffsetFromUTC = (Get-Date).Hour - ((Get-Date).ToUniversalTime()).Hour
            # Convert the UTC hour to local hour
            $StartHourLocal = $o.StartHourUTC + $OffsetFromUTC
            if ($StartHourLocal -ge 24) {$StartHourLocal = $StartHourLocal - 24}
            if ($StartHourLocal -lt 0) {$StartHourLocal = 24 + $StartHourLocal}
            $dtStartLocal = [datetime] $($StartHourLocal.ToString() + ":00")
            $EndHourLocal = $StartHourLocal + $o.RunHours
            if ($EndHourLocal -ge 24) {$EndHourLocal = $EndHourLocal - 24 }
            if ($EndHourLocal -lt 0) {$EndHourLocal = 24 + $EndHourLocal}
            $dtEndLocal = [datetime] $($EndHourLocal.ToString() + ":00")
            $Schedule = ("{0} to {1}, {2}" -f $dtStartLocal.ToShortTimeString(), $dtEndLocal.ToShortTimeString(), $tzName)
            $Status = $("{0} {1}" -f $o.Status.TimeStamp, $o.Status.Message)
            $object = New-Object psobject -Property @{
                Name = $InstanceName
                AutoStart = $o.AutoStart
                Enabled = $o.Enabled
                RunDays = [string]::Join(", ", $RunDays)
                StartHourUTC = $o.StartHourUTC
                StartHourLocal = $StartHourLocal
                RunHours = $o.RunHours
                Schedule = $Schedule
                Status = $Status
            }

            $InstanceSchedules += $object
        }
    }

    $InstanceSchedules | Select-Object Name, Enabled, AutoStart, StartHourUTC, StartHourLocal, RunHours, RunDays, Schedule, Status
} # End function Get-EC2RunSchedule

function Set-EC2RunSchedule {
    <#
    .SYNOPSIS
        Sets the run schedule for a given Amazon Ec2 instance.
    .DESCRIPTION
        Sets the run schedule for a given Amazon EC2 instance.
    .EXAMPLE
        Set-EC2RunSchedule -Name "AWUE1ADDC01" -Region "us-east-1" -Enabled -AutoStart -RunHours 13 -RunDays Monday, Tuesday, Wednesday, Thursday, Friday -StartHourUTC 13
    .EXAMPLE
        Set-EC2RunSchedule -Name "AWUE1ADDC01" -Region "us-east-1" -Enabled -AutoStart -RunHours 13 -RunDays 1,2,3,4,5 -StartHourUTC 13
    .PARAMETER Name
        The name of the instance.
    .PARAMETER Region
        The region of the instance. 
    .PARAMETER AutoStart
        If this is set, the instance will be started each time it is "in schedule"
    .PARAMETER Enabled
        If this is set, the schedule is enabled, else it's disabled (will be preserved but ignored)
    .PARAMETER RunHours
        The number of hours the instance should run. RunHours+StartHourUTC 
        defines the hours of operation that the instance is considered 
        "in schedule".
    .PARAMETER RunDays
        The days of the week the instance should run
    .PARAMETER StartHourUTC
        The hour (in UTC) that the instance should be started.
    .PARAMETER FilterPath
        An optional JSON file that specifies a list of instances, so that all instances in a subscription are affected.
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]

    Param
    (
        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the instance."
        )]
        [Parameter(
            ParameterSetName='CmdLineEnabledOnly',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the instance."
        )]
        [string] $Name,

        [Parameter(
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The region of the instance."
        )]
        [Parameter(
            ParameterSetName='CmdLineEnabledOnly',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The region of the instance."
        )]
        [string] $Region,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to automatically start the instance."
        )]
        [switch] $AutoStart,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to enable the schedule."
        )]
        [Parameter(
            ParameterSetName='CmdLineEnabledOnly',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to enable the schedule."
        )]
        [switch] $Enabled,
    
        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The number of hours the instance should run."
        )]
        [int] $RunHours,
    
        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The days of the week the instance should run.")]
        [System.DayOfWeek[]] $RunDays,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The hour (in UTC) that the instance should be started."
        )]
        [int] $StartHourUTC,
    
        [Parameter(
            Position=1,
            ParameterSetName='JSONFile',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="A JSON file that specifies a list of instances."
        )]
        [string] $FilterPath
    )

    # Determine which parameter set function was called with
    switch ($PSCmdlet.ParameterSetName) {
        "CmdLineEnabledOnly" {
            if ($Enabled) {
                $Instances = Find-Instances -Name $Name -Region $Region -Action Enable
            }
            else {
                $Instances = Find-Instances -Name $Name -Region $Region -Action Disable
            }
        }

        "JSONFile" {
            # Check if filterpath exists
            if  ( $FilterPath.Length -gt 0) {
                if (-not (Test-Path $FilterPath) ) {
                    Throw ("{0} is not a valid path." -f $FilterPath)
                }
            }
   
            # Find instances in the subscription that match the JSON in the filter file.
            $Instances = Find-Instances -FilterPath $FilterPath -Action Set

            # Make sure instances were found else display a warning message
            if ($Instances -eq $Null) {
                Throw ("No instances were found. Check the JSON document '{0}'" -f $FilterPath)
            }
        }

        "CmdLine" {
            # Sort the RunDays because the script author has OCD
            $RunDays = $RunDays | Sort-Object

            # Create a hastable for the status node
            $Status = @{
                TimeStamp = ""
                Message = ""
            }

            # Create a hashtable of the parameters
            $ht = @{
                AutoStart = $AutoStart.IsPresent
                Enabled = $Enabled.IsPresent
                RunHours = $RunHours
                RunDays = $RunDays
                StartHourUTC = $StartHourUTC
                Status = $Status
            }

            # Update the status fields
            Set-Status -Action Set -Status ([ref] $ht.Status)

            # Convert the hashtable to JSON minified
            $json = $ht | ConvertTo-Json -Compress

            $Instances = Find-Instances -Name $Name -Region $Region -Tag $json -Action Set

            # Make sure instances were found else display a warning message
            if ($Instances -eq $Null) {
                Throw ("No instances were found where the resource group name was '{0}' and the instance name was '{1}'" -f $ResourceGroupName, $Name)
            }
        }
    }

}# End function Set-EC2RunSchedule

Function Remove-EC2RunSchedule {
    <#
    .SYNOPSIS
        Removes the run schedule for a given Amazon EC2 instance.
    .DESCRIPTION
        Removes the run schedule for a given Amazon EC2 instance.
    .EXAMPLE
        Remove-EC2RunSchedule -Name "AWPUE1DC01" -Region "us-east-1"
    .EXAMPLE
        Remove-EC2RunSchedule -FilterPath ".\RunScheduleFilter.json"
    .PARAMETER Name
        The name of the instance.
    .PARAMETER Region
        The region of the instance.
    .PARAMETER FilterPath
        An optional JSON file that specifies a filter of instances, so that all instances in a subscription are not affected.
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]

    Param
    (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the instance."
        )]
        [string] $Name,

        [Parameter(
            Position=1,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The region of the instance."
        )]
        [string] $Region,

        [Parameter(
            Position=0,
            ParameterSetName='JSONFile',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="A JSON file that specifies a list of instances."
        )]
        [string] $FilterPath
    )

    # Determine which parameter set script was called with
    if ($PSCmdlet.ParameterSetName -eq "CmdLine") {
        # Set the tag parameter to an empty string and the Find-Instances cmdlet will remove the tag
        $Instances = Find-Instances -Name $Name -Region $Region -Action Remove
        # Make sure instances were found else display a warning message
        if ($Instances -eq $Null) {
            Write-Debug ("No instances were found where the resource group name was '{0}' and the instance name was '{1}'" -f $ResourceGroupName, $Name)
        }
    }
    else {
        # Check if filterpath exists
        if  ( $FilterPath.Length -gt 0) {
            if (-not (Test-Path $FilterPath) ) {
                Throw ("{0} is not a valid path." -f $FilterPath)
            }
        }
   
        # Find instances in the subscription that match the JSON in the filter file.
        $Instances = Find-Instances -FilterPath $FilterPath -Action Remove

        # Make sure instances were found else display a warning message
        if ($Instances -eq $Null) {
            Write-Debug ("No instances were found. Check the JSON document '{0}'" -f $FilterPath)
         }
    }
} # End function Remove-EC2RunSchedule

function Set-Status {
    <#
    .SYNOPSIS
        Sets the Status node in the RunSchedule tag.
    .DESCRIPTION
        Sets the Status node in the RunSchedule tag. 
    .EXAMPLE
        Set-Status -Action Set -Status ([ref] $object.Status)
    .PARAMETER Action
        The action, either "Started", "Stopped", "Set", "Enabled", "Disabled"
    .PARAMETER Status
        The Status object passed as a reference to a variable set in the caller. 
    #>

    Param (
        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The status node that will be set.",
            Position=0
       )]
        [ValidateSet("Started", "Stopped", "Set", "Enabled", "Disabled")] 
        [string] $Action,

        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The status node that will be set.",
            Position=1)]
        [ref] $Status
    )
    $dt = Get-Date -f u
    if ($global:PSCommandPath) {
        $Leaf = Split-Path -Path $global:PSCommandPath -Leaf
        $StatusMessage = $("{0} by {1}" -f $Action, $Leaf)
    } 
    else {
        $StatusMessage = $("{0} interactively by {1}" -f $Action, $env:UserName)
    }
    $Status.Value.TimeStamp = $dt
    $Status.Value.Message = $StatusMessage 
} # End function Set-Status

# End Module Functions

# This defines the name of the tag on the instance for all functions in the script 
$script:TagRS = "RunSchedule"

# Create an empty arraylist for monitoring and cleaning up jobs
[System.Collections.ArrayList] $script:Jobs = @()

# AWS PowerShell module must be explicitly loaded for non-interactive session (scheduled task)
Import-Module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"

Export-ModuleMember -Function Find-Instances
Export-ModuleMember -Function Set-Tag
Export-ModuleMember -Function Get-EC2RunSchedule
Export-ModuleMember -Function Set-EC2RunSchedule
Export-ModuleMember -Function Remove-EC2RunSchedule
Export-ModuleMember -Function Set-Status
# RunSchedule

## Overview

This set of PowerShell scripts is used automate the starting and stopping of Amazon Web Services (AWS) Elastic Cloud Computer (EC2) instances.

## Prerequisites

* An AWS IAM user account is required by the Compare-EC2RunSchedule.ps1 script. 
* An "always running" Windows computer is intended to run the Compare-EC2RunSchedule.ps1 as a scheduled task. 

## Script Overview

|Script|Description|
| --- | --- |
| EC2RunSchedule.psm1 | This PowerShell Script Module exports functions for getting, setting, and removing the RunSchedule tag from instances. |
| Compare-EC2RunSchedule.ps1 | This script imports the EC2RunSchedule.psm1 module and reads the RunSchedule tag on each instance to determine if the instance is "in schedule". |
| Install-EC2RunSchedule.ps1 | Installs the EC2RunSchedule.psm1 and EC2RunSchedule.psd1 files into the PowerShell modules path under %ProgramFiles%
| UnitTests.ps1 | Demonstrates the various command line methods for calling the cmdlets in the EC2RunSchedule module. |

### Module CmdLet Overview

| CmdLet | Description |
| --- | --- |
| Get-EC2RunSchedule | Gets the RunSchedule tag for the specified instance and displays it in a user friendly format. |
| Remove-EC2RunSchedule | Removes the RunSchedule tag for the specified instance. |
| Set-EC2RunSchedule | Sets the RunSchedule tag for the specified instance. |
| Find-Instances | Finds instances in the current subscription by pattern, either from command line parameters or JSON filter file. |

## Setup

### Create an AWS IAM User Account

http://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html

**TODO**: Work on script New-IAMUserAccount.ps1 and documentation around creating an AWS IAM user account with the least privileges to start/stop instances and change instance tags.

1. You will need an "always running" Windows computer that will execute the Compare-EC2RunSchedule.ps1 as a scheduled task. The computer can be either on-premises or in an IaaS cloud.
1. Create a local account on the Windows computer with a name such as "svcRunSchedule". 
1. Grant the svcRunSchedule local account the "Run as a batch job":
    1. Run the Local Security Policy application.
    1. Drill down to Security Settings\Local Policies\User Rights Assignment.
    1. Add the svcRunSchedule user to the "Log on as a batch job" policy.
1. Download all of the files from this solution into a directory on the Windows computer such as "C:\EC2RunSchedule"
1. Create a subdirectory named "Logs" under "C:\EC2RunSchedule". The Compare-EC2RunSchedule.ps1 will write it's log files to this subdirectory.
1. Start an elevated PowerShell session (as Administrator) and execute:
    ```powershell
    cacls.exe C:\EC2RunSchedule\Logs /E /T /G svcRunSchedule:C
    Set-ExecutionPolicy RemoteSigned
    C:\EC2RunSchedule\Install-EC2RunSchedule.ps1
    ```
    The first command grants the svcRunSchedule "Change" access to the C:\EC2RunSchedule\Logs and its children.
    The second command ensures that local PowerShell scripts are allowed to execute.
    The third command installs the EC2RunSchedule module in %ProgramFiles%\WindowsPowerShell\Modules. This makes the EC2RunSchedule's exported functions available to other scripts. Close the elevated PowerShell session when the script completes.
 1. In a non-elevated PowerShell session, execute:
    ```powershell
    cd \EC2RunSchedule
    C:\EC2RunSchedule\New-IAMUserAccount.ps1
    ```
    * When this script is run without parameters, it will prompt the user to sign into AWS.
    * A new AWS IAM user account will be created with the minimum set of IAM permissions required to to start and stop instances in the account. The IAM user account will also have the permission to create, remove and update tags on the instances in the subscription. 
1. Leave the PowerShell window open and note the output of the New-IAMUserAccount.ps1 script.     
1. In the non-elevated PowerShell session, execute:
    ```powershell
    runas.exe /user:svcRunSchedule powershell.exe

    ```
    This will start a new PowerShell session in the context of the local svcRunSchedule account.   
1. In the new PowerShell session running as svcRunSchedule execute these commands:
    ```powershell
    Set-AWSCredentials -AccessKey *\<AccessKey\>* -SecretKey *\<SecretKey\>* -StoreAs 'default'
    ```
    Where *\<AccessKey\>* is the Access Key of the new IAM user account and *\<SecretKey\>* is the Secret Key.
1. Edit the Compare-EC2RunSchedule.json file
    1. Update the FilterPath, if necessary, to the actual path of this Compare-EC2RunSchedule.json file. The FilterPath is used by Compare-EC2RunSchedule.ps1 to locate this .json file and load these values as variables.
    1. Update the SMTPServer value, if necessary. The Compare-EC2RunSchedule.ps1 will send email via this SMTP server when a fatal error occurs.
    1. Update the To value to the email recipient list that will receive mail sent when a fatal error occurs. Use semi-colons to separate email addresseses. 
1. In an elevated PowerShell (or cmd.exe) session execute:
    ```powershell
    schtasks.exe /Create /XML C:\EC2RunSchedule\EC2RunSchedule.xml /RU svcRunSchedule /RP * /TN "EC2RunSchedule"
    ```
    This creates the scheduled task that will execute the Compare-EC2RunSchedule.ps1 script every 15 minutes. It runs as svcRunSchedule.
1. Monitor the task in the Task Scheduler app. In the Actions pane, enable the Enable All Tasks History. 
1. View the output in C:\EC2RunSchedule\Logs\Compare-EC2RunSchedule*\<Date\>*. A new log file is created each day. 
1. Once you are confident that the schedule task executes correctly, reboot the Windows computer so that the task will execute every 15 minutes. 

## Managing the RunSchedule tag on instances

The EC2RunSchedule module contains functions for getting, setting, enabling, disabling and removing the RunSchedule tag from one or more instances. 

## RunSchedule Tag Design

The RunSchedule tag shall be applied to any instance that is indended to be stopped in an automated fashion. instances may be optionally started in an automated fashion. The RunSchedule tag is compound tag - it is a minified (single line) JSON document. In "pretty" format it looks like this:

```json
{
    "AutoStart": true,
    "Enabled":  true,
    "RunDays": [
        1,
        2,
        3,
        4,
        5
    ],
    "RunHours": 10,
    "StartHourUTC": 14,
    "Status": {
        "TimeStamp": "2017-05-11 12:51:57Z",
        "Message": "Instance started by Compare-EC2RunSchedule.ps1"
    }
    
}
```

### Tag Field descriptions

#### AutoStart

If this value is present and evaluates to [bool] true then the instance will be automatically started when it is considered "in schedule". If it is not present or evaluates to false, then the machine will not be started automatically if it is considered "in schedule" and not running.

#### Enabled

If this evaluates to [bool] true, then the instance will be processed by the Compare-EC2RunSchedule.ps1 script. It if evaluates to [bool] false then the instance will be ignored by the Compare-EC2RunSchedule.ps1 script. Setting it to false is handy for preserving the schedule but temporarily removing the instance from processing. 

#### RunDays

This is an array of integers with valid values 0 - 6 that correspond to the days of the week that the instance is intended to be running. 
RunDays is cast to an array of [System.DayOfWeek] internally by the PowerShell scripts. 

#### RunHours

The number of hours after StartHourUTC that the machine will be allowed to run.

#### StartHourUTC

The time in UTC that the instance's schedule starts each day in RunDays. 

#### Status

The TimeStamp and Message values in the Status are set by the Set-EC2RunSchedule.ps1 and Compare-EC2RunSchedule.ps1 scripts. Each time Compare-EC2RunSchedule.ps1 changes the state of the machine the Status fields are updated. 

## CmdLet Details

### Get-EC2RunSchedule

#### Get-EC2RunSchedule Description

Gets the run schedule for a given EC2 instance.

#### Get-EC2RunSchedule Examples

```powershell
Get-EC2RunSchedule -FilterPath $FilterPath
Get-EC2RunSchedule -Name 'AWUE1*' -Region 'us-east-1'
```

#### Get-EC2RunSchedul eOutput (defaults to list view)

```powershell
Name           : AWUE1ADDC01
AutoStart      : False
StartHourUTC   : 13
StartHourLocal : 8
RunHours       : 10
RunDays        : Monday, Tuesday, Wednesday, Thursday, Friday
Schedule       : 8:00 AM to 6:00 PM, Eastern Standard Time
Status         : 2017-05-19 15:32:07Z Run schedule set by
```

### Set-EC2RunSchedule

#### Set-EC2RunSchedule Description

Sets the run schedule for a given EC2 instance.

#### Set-EC2RunSchedule Example

Using the integer values for the RunDays parameter:

```powershell
Set-EC2RunSchedule -Name 'AWUE101' -Region 'us-east-1' -Verbose -Enabled -RunHours 10 -RunDays 1,2,3,4,5 -StartHourUTC 13 -AutoStart
```

Or that names days of the week can be used with the RunDays parameter:

```powershell
Set-EC2RunSchedule -Name 'AWUE1*' -Region 'us-east-1' -Verbose -Enabled -RunHours 13 -RunDays Monday,Wednesday,Friday -StartHourUTC 13 -AutoStart
```

#### Set-EC2RunSchedule Output

This cmdlet does not output to StdOut. Use the '-Verbose' parameter to see verbose output. This can be useful as the cmdlet won't return until all background jobs are finished. 

### Remove-EC2RunSchedule

#### Remove-EC2RunSchedule Description

Remove the run schedule for a given EC2 instance.

#### Remove-EC2RunSchedule Example

```powershell
Remove-EC2RunSchedule -FilterPath $FilterPath -Verbose
```

#### Remove-EC2RunSchedule Output

This cmdlet does not output to StdOut. Use the '-Verbose' parameter to see verbose output. This can be useful as the cmdlet won't return until all background jobs are finished.

### Compare-EC2RunSchedule.ps1 Script

#### Compare-EC2RunSchedule.ps1 Description

The Compare-EC2RunSchedule.ps1 script is where the magic happens - it actually starts and stops instances based on the contents of each instance's EC2RunSchedule tag. It is intended to be run as a scheduled task on a Windows machine that is "always on". The machine could be on-premises on in the cloud. The scheduled task could be configured to run every 15 minutes.

#### Compare-EC2RunSchedule.ps1 Design

The Compare-EC2RunSchedule.ps1 script has no command line parameters. Instead, it reads the Compare-EC2RunSchedule.json which defines script-wide variables used by the script.

##### The Compare-EC2RunSchedule.json file

 An example Compare-EC2RunSchedule.json:

```json
{
    "Variables":  [
        {
            "name": "FilterPath",
            "value": "C:\\EC2RunSchedule\\EC2RunSchedule.json"
        },
        {
            "name": "SMTPServer",
            "value": "mail.mydomain.com"
        },
        {
            "name": "Domain",
            "value": "mydomain.com"
        },
        {
            "name": "To",
            "value": "siloreed@hotmail.com"
        }
    ]
}
```

##### Variables

* FilterPath: An optional JSON file that specifies a filter of instances, so that all instances in a subscription are not examined. 
* SMTPServer: The name or IP address of an SMTP that will be used for sending fatal errors via email
* To: The recipient list of email addresses (semi-colon separated)

#### Compare-EC2RunSchedule.ps1 Example

.\Compare-EC2RunSchedule.ps1

## Example instance filter list

The Get-EC2RunSchedule, Set-EC2RunSchedule, and Remove-EC2RunSchedule cmdlet have an optional -FilterPath command line argument that can be used to specify a list of resource groups and instances to act upon. The FilterPath file is a JSON document that may also contain the RunSchedule for instances, which is handy for setting the RunSchedule for many machines at one time. The example of this file looks like this (although location is not currently implemented in the code):

```json
{
    "comments": "This is the list of Amazon EC2 instances that could be checked by the Compare-EC2RunSchedule script.",
    "name": "ITEA Instances",
    "regions": [
        {
            "name": "us-east-1",
            "instances": [
                {
                    "name": "AWUE1ADDC01",
                    "RunSchedule": {
                        "Enabled":  true,
                        "AutoStart": true,
                        "RunDays": [
                            1,
                            2,
                            3,
                            4,
                            5
                        ],
                        "RunHours": 8,
                        "StartHourUTC": 13,
                        "Status": {
                            "TimeStamp": "",
                            "Message": ""
                        }
                    }
                },
                {
                    "name": "AWUE1FILE01",
                    "RunSchedule": {
                        "Enabled":  true,
                        "AutoStart": true,
                        "RunDays": [
                            1,
                            2,
                            3,
                            4,
                            5
                        ],
                        "RunHours": 4,
                        "StartHourUTC": 13,
                        "Status": {
                            "TimeStamp": "",
                            "Message": ""
                        }
                    }
                }
            ]
        },
        {
            "name": "us-west-1",
            "instances": [
                {
                    "name": "AWUW1FILE01",
                    "RunSchedule": {
                        "Enabled":  true,
                        "AutoStart": true,
                        "RunDays": [
                            1,
                            2,
                            3,
                            4,
                            5
                        ],
                        "RunHours": 2,
                        "StartHourUTC": 13,
                        "Status": {
                            "TimeStamp": "",
                            "Message": ""
                        }
                    }
                }
            ]
        }
    ]
}
```

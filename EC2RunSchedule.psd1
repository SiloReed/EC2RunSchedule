@{

# Script module or binary module file associated with this manifest.
# RootModule = ''

# Version number of this module.
ModuleVersion = '1.0.1.0'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '72672abe-998a-46e1-a0c6-0f384a072286'

# Author of this module
Author = 'Jeff Reed'

# Company or vendor of this module
CompanyName = 'Jeff Reed'

# Copyright statement for this module
Copyright = '(c) 2018 Jeff Reed. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Functions shared with the family of scripts in the EC2RunSchedule solution.'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.0'

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
CLRVersion = '2.0'

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @('AWSPowerShell')

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
NestedModules = @('EC2RunSchedule.psm1')

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @(  'Find-Instances',
                        'Set-Tag',
                        'Get-EC2RunSchedule',
                        'Set-EC2RunSchedule',
                        'Remove-EC2RunSchedule',
                        'Set-Status'
                        )

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

}


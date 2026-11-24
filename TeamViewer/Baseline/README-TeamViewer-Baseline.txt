TeamViewer Host - company assignment Configuration Baseline (SCCM)
=================================================================

Purpose
-------
Fixes devices that already run the current TeamViewer Host but are NOT assigned to the
Stratum Reservoir company (rollout configuration {37f34e50-cf20-11ef-9553-f92970a4d113}).
Runs on a schedule, so it also catches devices that lose their assignment later.

Files
-----
Discover-TeamViewerAssignment.ps1   SCCM discovery script -> outputs "Compliant" / "NonCompliant" (always exits 0)
Detect-TeamViewerAssignment-Intune.ps1  Intune detection script (exit 1 = remediation needed)
Remediate-TeamViewerAssignment.ps1  Remediation script -> runs TeamViewer.exe assignment
Log on clients: C:\Windows\Logs\Software\TeamViewer_AssignmentRemediation.log

How "assigned" is checked (registry, written by TeamViewer on assignment)
---------------------------------------------------------------------
HKLM\SOFTWARE\TeamViewer\DeviceManagementV2  ManagementId               must exist
HKLM\SOFTWARE\TeamViewer                     ManagedDeviceV2AssignmentId must equal {37f34e50-cf20-11ef-9553-f92970a4d113}
Devices still carrying the identity cloned by the old package (ManagementId {b7113481-...})
are reported NonCompliant but NOT remediated here - the TeamViewer application package fixes them.

SCCM setup
----------
1. Assets and Compliance > Compliance Settings > Configuration Items > Create Configuration Item
   - Name: TeamViewer Host - Company Assignment
   - Type: Windows Desktops and Servers (custom), Settings for devices managed with the ConfigMgr client
   - Supported platforms: Windows 10 / Windows 11
2. Settings > New
   - Setting type: Script     Data type: String
   - Discovery script:   PowerShell, paste Discover-TeamViewerAssignment.ps1
   - Remediation script: PowerShell, paste Remediate-TeamViewerAssignment.ps1
   - Leave "Run scripts by using the logged on user credentials" UNCHECKED (runs as SYSTEM)
3. Compliance Rules > New
   - Rule type: Value     The value returned by the specified script: Equals  Compliant
   - Tick "Run the specified remediation script when this setting is noncompliant"
   - Noncompliance severity: Warning
4. Create Configuration Baseline "TeamViewer Host - Company Assignment" and add the CI.
5. Deploy the baseline to the workstation collection:
   - Tick "Remediate noncompliant rules when supported"
   - Schedule: daily
6. Client settings: PowerShell execution policy must be "Bypass" (or sign the scripts).

Order of operations
-------------------
- Deploy the TeamViewer application first (installs/upgrades to 15.83.7, resets cloned devices, assigns).
- The baseline then sweeps up any device that is installed but still unassigned.

Intune equivalent
-----------------
Devices > Scripts and remediations > Create: detection = Detect-TeamViewerAssignment-Intune.ps1,
remediation = Remediate-TeamViewerAssignment.ps1, run as system, 64-bit PowerShell.

Troubleshooting (remediation log exit codes)
--------------------------------------------
403 not online / 405 timeout -> network/proxy to TeamViewer cloud; retried next cycle
408 denied by policy         -> device is assigned elsewhere with a policy blocking re-assignment;
                                disable that policy in the TeamViewer console or remove the device there
400 invalid argument         -> check the assignment ID in the remediation script

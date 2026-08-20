Option Explicit

Dim shell, fileSystem, scriptDirectory, powershellPath, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") _
    & "\System32\WindowsPowerShell\v1.0\powershell.exe"
command = """" & powershellPath & """ -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ _
    & fileSystem.BuildPath(scriptDirectory, "Watch-CodexDesktop.ps1") & """"
shell.Run command, 0, False

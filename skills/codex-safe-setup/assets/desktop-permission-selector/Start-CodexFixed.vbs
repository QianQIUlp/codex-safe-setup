Option Explicit

Dim shell, fileSystem, scriptDirectory, powershellPath, command, waitForExit, exitCode
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") _
    & "\System32\WindowsPowerShell\v1.0\powershell.exe"
command = """" & powershellPath & """ -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ _
    & fileSystem.BuildPath(scriptDirectory, "Start-CodexFixed.ps1") & """"
waitForExit = False
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) <> "-validateonly" Then WScript.Quit 87
    command = command & " -ValidateOnly"
    waitForExit = True
End If
exitCode = shell.Run(command, 0, waitForExit)
If waitForExit Then WScript.Quit exitCode

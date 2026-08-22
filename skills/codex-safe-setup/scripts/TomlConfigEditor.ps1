#requires -Version 7.0
<#
Structural TOML editor for the codex-safe-setup managed configuration surface.

This module is deliberately NOT a full TOML parser. It is a scope-aware structural
analyzer that understands exactly what the plugin needs in order to edit a real
user configuration safely:

  1. Where every top-level key and section actually lives (the v0.2.x incident:
     `default_permissions`, `notify`, `model` and friends silently became members
     of `[model_providers.openrouter]` / `[windows]` after an unrelated table was
     inserted above them).
  2. Multi-line values (arrays spanning lines, multi-line basic/literal strings)
     so that a `[section]`-looking fragment inside a value is never mistaken for
     a header.
  3. The two codex-safe-setup managed regions plus the retired single-block
     layout, including their ordering contracts.

Ownership rule enforced here: plugin-owned keys are repaired automatically;
keys owned by other writers are reported only.
#>

Set-StrictMode -Version Latest

$script:CssTomlTopBlockStart    = '# >>> codex-safe-setup top-level >>>'
$script:CssTomlTopBlockEnd      = '# <<< codex-safe-setup top-level <<<'
$script:CssTomlProfileStart     = '# >>> codex-safe-setup profiles >>>'
$script:CssTomlProfileEnd       = '# <<< codex-safe-setup profiles <<<'
$script:CssTomlLegacyStart      = '# >>> codex-safe-setup managed >>>'
$script:CssTomlLegacyEnd        = '# <<< codex-safe-setup managed <<<'

# Keys that are only valid at the TOML top level in Codex's public config schema.
# Any occurrence under a [table] is either a plugin bug or an external writer
# accident; both must be surfaced instead of silently ignored.
$script:CssTopLevelOnlyKeys = @(
    'default_permissions', 'approval_policy', 'approvals_reviewer',   # plugin-owned
    'model', 'model_reasoning_effort', 'model_verbosity',
    'notify', 'web_search', 'service_tier'                            # foreign-owned
)
$script:CssPluginOwnedTopLevelKeys = @('default_permissions', 'approval_policy', 'approvals_reviewer')

function Get-CssTomlNewlineStyle {
    param([AllowEmptyString()][string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    if ($Text.Contains("`n")) { return "`n" }
    return [Environment]::NewLine
}

function Get-CssTomlLines {
    param([AllowEmptyString()][string]$Text)
    $normalized = $Text -replace "`r`n", "`n"
    if ($normalized.EndsWith("`n")) {
        $normalized = $normalized.Substring(0, $normalized.Length - 1)
    }
    return @($normalized -split "`n")
}

function Join-CssTomlLines {
    param([string[]]$Lines, [Parameter(Mandatory)][string]$Newline)
    return ($Lines -join $Newline)
}

function Test-CssLineInsideValue {
    # Returns $true when, given the running parser state, the line is part of a
    # multi-line string or array rather than a fresh construct.
    param([bool]$InMultilineBasic, [bool]$InMultilineLiteral, [int]$BracketDepth)
    return $InMultilineBasic -or $InMultilineLiteral -or $BracketDepth -gt 0
}

function Get-CssManagedMarkerKind {
    param([AllowEmptyString()][string]$TrimmedLine)
    switch ($TrimmedLine) {
        $script:CssTomlTopBlockStart { return 'TopStart' }
        $script:CssTomlTopBlockEnd   { return 'TopEnd' }
        $script:CssTomlProfileStart  { return 'ProfileStart' }
        $script:CssTomlProfileEnd    { return 'ProfileEnd' }
        $script:CssTomlLegacyStart   { return 'LegacyStart' }
        $script:CssTomlLegacyEnd     { return 'LegacyEnd' }
        default { return $null }
    }
}

function Get-CssTomlDocument {
    <#
    Parses config text into a structural document.

    Output object properties:
      Elements  : ordered list of line records
                  { Index, Text, Kind (Blank|Comment|Section|ArrayTable|KeyValue|Managed|Other),
                    SectionPath ('' = top level), Key, ManagedRegion (or $null) }
      Diagnostics : list of { Code, Severity, LineNumber, SectionPath, Key, Message }
    #>
    param(
        [AllowEmptyString()][string]$Text,
        [switch]$IncludeDiagnostics
    )

    $newline = Get-CssTomlNewlineStyle -Text $Text
    $elements = [Collections.Generic.List[object]]::new()
    $diagnostics = [Collections.Generic.List[object]]::new()

    $sectionPath = ''
    $inMultilineBasic = $false      # """
    $inMultilineLiteral = $false    # '''
    $bracketDepth = 0
    $seenTables = @{}
    $seenTopLevelKeys = @{}
    $managedRegion = $null
    $topBlockSeenAt = -1
    $firstRealSectionAt = -1
    $profileBlockSeenAt = -1
    $legacyBlockSeenAt = -1
    $openMarkers = [Collections.Generic.List[string]]::new()

    $index = -1
    foreach ($line in (Get-CssTomlLines -Text $Text -Newline $newline)) {
        $index++
        $trimmed = $line.Trim()

        $markerKind = Get-CssManagedMarkerKind -TrimmedLine $trimmed
        if ($null -ne $markerKind) {
            switch -Regex ($markerKind) {
                'Start$' {
                    $openMarkers.Add($markerKind)
                    switch ($markerKind) {
                        'TopStart' {
                            if ($topBlockSeenAt -ge 0) {
                                $diagnostics.Add([pscustomobject]@{ Code='DuplicateManagedBlock'; Severity='Error'; LineNumber=$index+1; SectionPath=''; Key=''; Message='codex-safe-setup top-level block appears more than once.' })
                            }
                            $topBlockSeenAt = $index
                        }
                        'ProfileStart' {
                            if ($profileBlockSeenAt -ge 0) {
                                $diagnostics.Add([pscustomobject]@{ Code='DuplicateManagedBlock'; Severity='Error'; LineNumber=$index+1; SectionPath=''; Key=''; Message='codex-safe-setup profiles block appears more than once.' })
                            }
                            $profileBlockSeenAt = $index
                        }
                        'LegacyStart' {
                            if ($legacyBlockSeenAt -ge 0) {
                                $diagnostics.Add([pscustomobject]@{ Code='DuplicateManagedBlock'; Severity='Error'; LineNumber=$index+1; SectionPath=''; Key=''; Message='retired codex-safe-setup managed block appears more than once.' })
                            }
                            $legacyBlockSeenAt = $index
                        }
                    }
                }
                'End$' {
                    $expected = $markerKind.Substring(0, $markerKind.Length - 3) + 'Start'
                    if (-not $openMarkers.Contains($expected)) {
                        $diagnostics.Add([pscustomobject]@{ Code='UnmatchedManagedEnd'; Severity='Error'; LineNumber=$index+1; SectionPath=''; Key=''; Message="Managed block end marker without a matching start: $trimmed" })
                    } else {
                        [void]$openMarkers.Remove($expected)
                    }
                }
            }
            $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind='Managed'; SectionPath=$sectionPath; Key=$null; ManagedRegion=$markerKind })
            continue
        }

        if ($openMarkers.Count -gt 0) {
            # Content inside a managed region keeps its structural meaning but is tagged.
            $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind=(Get-ElementKind -Line $line); SectionPath=$sectionPath; Key=(Get-KeyFromLine -Line $line); ManagedRegion=($openMarkers[-1]) })
            Update-ValueState -Line $line -InMultilineBasic ([ref]$inMultilineBasic) -InMultilineLiteral ([ref]$inMultilineLiteral) -BracketDepth ([ref]$bracketDepth)
            continue
        }

        if (Test-CssLineInsideValue -InMultilineBasic $inMultilineBasic -InMultilineLiteral $inMultilineLiteral -BracketDepth $bracketDepth) {
            $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind='Continuation'; SectionPath=$sectionPath; Key=$null; ManagedRegion=$null })
            Update-ValueState -Line $line -InMultilineBasic ([ref]$inMultilineBasic) -InMultilineLiteral ([ref]$inMultilineLiteral) -BracketDepth ([ref]$bracketDepth)
            continue
        }

        if ($trimmed -eq '') {
            $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind='Blank'; SectionPath=$sectionPath; Key=$null; ManagedRegion=$null })
            continue
        }
        if ($trimmed.StartsWith('#')) {
            $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind='Comment'; SectionPath=$sectionPath; Key=$null; ManagedRegion=$null })
            continue
        }

        if ($trimmed.StartsWith('[')) {
            $isArrayTable = $trimmed.StartsWith('[[')
            if ($isArrayTable) {
                $headerText = [regex]::Match($trimmed, '^\[\[(.+?)\]\]').Groups[1].Value.Trim()
            } else {
                $headerText = [regex]::Match($trimmed, '^\[(.+?)\]\s*(?:#.*)?$').Groups[1].Value.Trim()
            }
            if ($headerText) {
                $kind = if ($isArrayTable) { 'ArrayTable' } else { 'Section' }
                $sectionPath = $headerText
                if (-not $isArrayTable) {
                    if ($seenTables.ContainsKey($headerText)) {
                        $diagnostics.Add([pscustomobject]@{ Code='DuplicateTableHeader'; Severity='Error'; LineNumber=$index+1; SectionPath=$headerText; Key=''; Message="Table [$headerText] is defined more than once." })
                    } else { $seenTables[$headerText] = $true }
                }
                if ($firstRealSectionAt -lt 0 -and -not $isArrayTable) { $firstRealSectionAt = $index }
                $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind=$kind; SectionPath=$sectionPath; Key=$null; ManagedRegion=$null })
                continue
            }
        }

        $key = Get-KeyFromLine -Line $line
        if ($null -ne $key) {
            $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind='KeyValue'; SectionPath=$sectionPath; Key=$key; ManagedRegion=$null })
            Update-ValueState -Line $line -InMultilineBasic ([ref]$inMultilineBasic) -InMultilineLiteral ([ref]$inMultilineLiteral) -BracketDepth ([ref]$bracketDepth)
            if ($IncludeDiagnostics -and $sectionPath -eq '') {
                if ($seenTopLevelKeys.ContainsKey($key)) {
                    $diagnostics.Add([pscustomobject]@{ Code='DuplicateTopLevelKey'; Severity='Error'; LineNumber=$index+1; SectionPath=''; Key=$key; Message="Key '$key' is defined more than once at the TOML top level." })
                } else { $seenTopLevelKeys[$key] = $true }
            }
            continue
        }

        $elements.Add([pscustomobject]@{ Index=$index; Text=$line; Kind='Other'; SectionPath=$sectionPath; Key=$null; ManagedRegion=$null })
        Update-ValueState -Line $line -InMultilineBasic ([ref]$inMultilineBasic) -InMultilineLiteral ([ref]$inMultilineLiteral) -BracketDepth ([ref]$bracketDepth)
    }

    if ($openMarkers.Count -gt 0) {
        foreach ($marker in $openMarkers) {
            $diagnostics.Add([pscustomobject]@{ Code='UnclosedManagedBlock'; Severity='Error'; LineNumber=$index+1; SectionPath=''; Key=''; Message="Managed block started but never closed: $marker" })
        }
    }
    if ($inMultilineBasic -or $inMultilineLiteral -or $bracketDepth -gt 0) {
        $diagnostics.Add([pscustomobject]@{ Code='UnterminatedValue'; Severity='Error'; LineNumber=$index+1; SectionPath=$sectionPath; Key=''; Message='File ends inside a multi-line string, array, or inline table.' })
    }
    if ($IncludeDiagnostics) {
        foreach ($element in $elements) {
            if ($element.Kind -eq 'KeyValue' -and $element.SectionPath -ne '' -and $script:CssTopLevelOnlyKeys -contains $element.Key) {
                $severity = if ($script:CssPluginOwnedTopLevelKeys -contains $element.Key) { 'Error' } else { 'Warning' }
                $owner = if ($severity -eq 'Error') { 'plugin-owned' } else { 'foreign' }
                $diagnostics.Add([pscustomobject]@{
                    Code='MisplacedTopLevelKey'; Severity=$severity; LineNumber=$element.Index+1
                    SectionPath=$element.SectionPath; Key=$element.Key
                    Message=("Key '{0}' only belongs at the TOML top level but sits under [{1}] ({2}). " -f $element.Key, $element.SectionPath, $owner) +
                           $(if ($owner -eq 'plugin-owned') { 'Re-run Install-CodexSafety.ps1 to repair automatically.' } else { 'This file was edited by another writer; fix manually or pass -RepairForeignMisplacedKeys.' })
                })
            }
        }
        if ($topBlockSeenAt -ge 0 -and $firstRealSectionAt -ge 0 -and $topBlockSeenAt -gt $firstRealSectionAt) {
            $diagnostics.Add([pscustomobject]@{ Code='ManagedTopLevelBlockAfterSections'; Severity='Error'; LineNumber=$topBlockSeenAt+1; SectionPath=''; Key=''; Message='The codex-safe-setup top-level block must appear before the first [table] header.' })
        }
    }

    return [pscustomobject]@{
        NewlineStyle = $newline
        Elements = $elements
        Diagnostics = $diagnostics
        TopBlockStartIndex = $topBlockSeenAt
        ProfileBlockStartIndex = $profileBlockSeenAt
        LegacyBlockStartIndex = $legacyBlockSeenAt
        FirstSectionIndex = $firstRealSectionAt
    }
}

function Get-ElementKind {
    param([string]$Line)
    $trimmed = $Line.Trim()
    if ($trimmed -eq '') { return 'Blank' }
    if ($trimmed.StartsWith('#')) { return 'Comment' }
    if ($null -ne (Get-KeyFromLine -Line $Line)) { return 'KeyValue' }
    if ($trimmed.StartsWith('[')) { return 'Section' }
    return 'Other'
}

function Get-KeyFromLine {
    param([string]$Line)
    # Bare keys, dotted keys, and quoted keys followed by '='.
    $match = [regex]::Match($Line, '^\s*("[^"]*"|''[^'']*''|[A-Za-z0-9_.-]+)\s*=')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Update-ValueState {
    param(
        [string]$Line,
        [ref]$InMultilineBasic,
        [ref]$InMultilineLiteral,
        [ref]$BracketDepth
    )
    # Character scanner tracking quotes, escapes, triple-quote toggles, and [] depth.
    $i = 0; $n = $Line.Length
    while ($i -lt $n) {
        if ($InMultilineLiteral.Value) {
            if ($Line.Substring($i).StartsWith("'''")) { $InMultilineLiteral.Value = $false; $i += 3 } else { $i++ }
            continue
        }
        if ($InMultilineBasic.Value) {
            if ($Line.Substring($i).StartsWith('"""')) { $InMultilineBasic.Value = $false; $i += 3 }
            elseif ($Line[$i] -eq '\') { $i += 2 } else { $i++ }
            continue
        }
        $c = $Line[$i]
        if ($Line.Substring($i).StartsWith('"""')) { $InMultilineBasic.Value = $true; $i += 3; continue }
        if ($Line.Substring($i).StartsWith("'''")) { $InMultilineLiteral.Value = $true; $i += 3; continue }
        if ($c -eq '"') {
            $i++
            while ($i -lt $n) {
                if ($Line[$i] -eq '\') { $i += 2; continue }
                if ($Line[$i] -eq '"') { $i++; break }
                $i++
            }
            continue
        }
        if ($c -eq '#') { break }  # comment until EOL (only reachable outside strings)
        if ($c -eq "'") {
            $i++
            while ($i -lt $n -and $Line[$i] -ne "'") { $i++ }
            $i++
            continue
        }
        if ($c -eq '[') { $BracketDepth.Value++; $i++; continue }
        if ($c -eq ']') { if ($BracketDepth.Value -gt 0) { $BracketDepth.Value-- }; $i++; continue }
        if ($c -eq '{') { $BracketDepth.Value++; $i++; continue }
        if ($c -eq '}') { if ($BracketDepth.Value -gt 0) { $BracketDepth.Value-- }; $i++; continue }
        $i++
    }
}

function Repair-CssMisplacedPluginKeys {
    <#
    Removes plugin-owned keys found under non-top-level sections so the installer
    can re-insert them inside the managed top-level block. Foreign keys are left
    untouched and remain visible through diagnostics.
    #>
    param([AllowEmptyString()][string]$Text)

    $document = Get-CssTomlDocument -Text $Text
    $dropIndexes = @{}
    foreach ($element in $document.Elements) {
        if ($element.Kind -eq 'KeyValue' -and $element.SectionPath -ne '' -and
            $script:CssPluginOwnedTopLevelKeys -contains $element.Key) {
            $dropIndexes[$element.Index] = $true
        }
    }
    if ($dropIndexes.Count -eq 0) {
        return [pscustomobject]@{ Text=$Text; RemovedCount=0 }
    }
    $kept = @($document.Elements | Where-Object { -not $dropIndexes.ContainsKey($_.Index) } | ForEach-Object Text)
    return [pscustomobject]@{
        Text = Join-CssTomlLines -Lines $kept -Newline $document.NewlineStyle
        RemovedCount = $dropIndexes.Count
    }
}

function Remove-CssAllManagedRegions {
    <#
    Removes every generation of managed content: the retired single block and
    both current blocks. Used by install/upgrade before regenerating state.
    #>
    param([AllowEmptyString()][string]$Text)

    $document = Get-CssTomlDocument -Text $Text
    $kept = @($document.Elements | Where-Object { $_.Kind -ne 'Managed' } | ForEach-Object Text)
    return Join-CssTomlLines -Lines $kept -Newline $document.NewlineStyle
}

function Set-CssTomlTopLevelBlock {
    <#
    Inserts (or replaces) the managed top-level block strictly BEFORE the first
    real section header, skipping any leading comment/blank preamble so user
    comments stay above it.
    #>
    param(
        [AllowEmptyString()][string]$Text,
        [AllowEmptyCollection()][string[]]$BlockLines
    )

    if ($BlockLines -eq $null -or $BlockLines.Count -eq 0) { return $Text }

    $document = Get-CssTomlDocument -Text $Text
    $newline = $document.NewlineStyle

    # Drop any existing top-level managed region (markers and its body).
    $bodyLines = [Collections.Generic.List[string]]::new()
    if ($document.TopBlockStartIndex -ge 0) {
        $inRegion = $false
        foreach ($element in $document.Elements) {
            if ($element.Kind -eq 'Managed') {
                if ($element.ManagedRegion -eq 'TopStart') { $inRegion = $true; continue }
                if ($element.ManagedRegion -eq 'TopEnd') { $inRegion = $false; continue }
            }
            if (-not $inRegion) { $bodyLines.Add($element.Text) }
        }
    } else {
        foreach ($element in $document.Elements) { $bodyLines.Add($element.Text) }
    }

    # Find insertion point: after leading blanks/comments, before first Section/ArrayTable/KeyValue-of-user-content.
    $insertAt = 0
    for ($i = 0; $i -lt $bodyLines.Count; $i++) {
        $trimmed = $bodyLines[$i].Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { $insertAt = $i + 1; continue }
        break
    }

    $result = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $insertAt; $i++) { $result.Add($bodyLines[$i]) }
    foreach ($blockLine in $BlockLines) { $result.Add($blockLine) }
    for ($i = $insertAt; $i -lt $bodyLines.Count; $i++) { $result.Add($bodyLines[$i]) }

    return Join-CssTomlLines -Lines $result.ToArray() -Newline $newline
}

function Add-CssTomlRelocatedUserLines {
    <#
    Moves the supplied key=value lines out of whatever [table] they currently
    sit under and re-inserts them at the TOML top level, immediately before the
    first structural element (section header, key/value, or managed marker).

    Collision policy: a source line whose key already exists at the TOML top
    level, or whose key was already claimed by an earlier source line in this
    same batch, is NOT relocated — it stays where it is and is reported in
    SkippedKeys so the caller can surface the conflict. This keeps the repair
    honest: the plugin never silently chooses between two user-owned values.
    #>
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SourceLines
    )

    $result = [pscustomobject]@{
        Text           = $Text
        RelocatedCount = 0
        SkippedKeys    = [string[]]@()
    }
    if ($SourceLines.Count -eq 0) { return $result }

    $document = Get-CssTomlDocument -Text $Text
    $newline = $document.NewlineStyle

    $existingTopLevelKeys = @{}
    foreach ($element in $document.Elements) {
        if ($element.Kind -eq 'KeyValue' -and $element.SectionPath -eq '' -and $null -ne $element.Key) {
            $existingTopLevelKeys[$element.Key] = $true
        }
    }

    $sourceSet = @{}
    foreach ($sourceLine in $SourceLines) { $sourceSet[$sourceLine.TrimEnd()] = $true }

    $dropIndexes = @{}
    $claimedKeys = @{}
    $skipped = [Collections.Generic.List[string]]::new()
    foreach ($element in $document.Elements) {
        if ($element.Kind -ne 'KeyValue' -or $element.SectionPath -eq '') { continue }
        if (-not $sourceSet.ContainsKey($element.Text.TrimEnd())) { continue }

        $key = $element.Key
        if ($existingTopLevelKeys.ContainsKey($key) -or $claimedKeys.ContainsKey($key)) {
            if (-not $skipped.Contains($key)) { $skipped.Add($key) }
            continue
        }
        $claimedKeys[$key] = $true
        $dropIndexes[$element.Index] = $true
    }

    if ($dropIndexes.Count -eq 0) {
        $result.SkippedKeys = @($skipped)
        return $result
    }

    $bodyLines = [Collections.Generic.List[string]]::new()
    $firstStructuralIndex = -1
    foreach ($element in $document.Elements) {
        if (-not $dropIndexes.ContainsKey($element.Index)) {
            $bodyLines.Add($element.Text)
            if ($firstStructuralIndex -lt 0 -and $element.Kind -in @('Section', 'ArrayTable', 'KeyValue', 'Managed')) {
                $firstStructuralIndex = $bodyLines.Count - 1
            }
        }
    }

    $relocatedLines = @()
    foreach ($element in $document.Elements) {
        if ($dropIndexes.ContainsKey($element.Index)) { $relocatedLines += $element.Text }
    }

    $final = [Collections.Generic.List[string]]::new()
    if ($firstStructuralIndex -lt 0) {
        foreach ($line in $bodyLines) { $final.Add($line) }
        foreach ($line in $relocatedLines) { $final.Add($line) }
    }
    else {
        for ($i = 0; $i -lt $firstStructuralIndex; $i++) { $final.Add($bodyLines[$i]) }
        foreach ($line in $relocatedLines) { $final.Add($line) }
        for ($i = $firstStructuralIndex; $i -lt $bodyLines.Count; $i++) { $final.Add($bodyLines[$i]) }
    }

    $result.Text = Join-CssTomlLines -Lines $final.ToArray() -Newline $newline
    $result.RelocatedCount = $relocatedLines.Count
    $result.SkippedKeys = @($skipped)
    return $result
}

function Set-CssTomlProfilesBlock {
    <#
    Appends (or replaces) the managed profiles block at the very end of the file.
    #>
    param(
        [AllowEmptyString()][string]$Text,
        [AllowEmptyCollection()][string[]]$BlockLines
    )

    $document = Get-CssTomlDocument -Text $Text
    $newline = $document.NewlineStyle

    $bodyLines = [Collections.Generic.List[string]]::new()
    if ($document.ProfileBlockStartIndex -ge 0) {
        $inRegion = $false
        foreach ($element in $document.Elements) {
            if ($element.Kind -eq 'Managed') {
                if ($element.ManagedRegion -eq 'ProfileStart') { $inRegion = $true; continue }
                if ($element.ManagedRegion -eq 'ProfileEnd') { $inRegion = $false; continue }
            }
            if (-not $inRegion) { $bodyLines.Add($element.Text) }
        }
    } else {
        foreach ($element in $document.Elements) { $bodyLines.Add($element.Text) }
    }

    while ($bodyLines.Count -gt 0 -and $bodyLines[-1].Trim() -eq '') { $bodyLines.RemoveAt($bodyLines.Count - 1) }
    if ($bodyLines.Count -gt 0) { $bodyLines.Add('') ; $bodyLines.Add('') }
    foreach ($blockLine in $BlockLines) { $bodyLines.Add($blockLine) }

    return Join-CssTomlLines -Lines $bodyLines.ToArray() -Newline $newline
}

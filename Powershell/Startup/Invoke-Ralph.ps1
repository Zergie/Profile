#Requires -Version 7.0

<#
.SYNOPSIS
    Implements local-tracker features iteratively with Codex or GitHub Copilot CLI.

.DESCRIPTION
    Runs one bounded agent invocation per iteration. Without Feature, the agent
    selects and continues the highest-priority unfinished feature below
    .scratch/<feature>/issues. With Feature, only that active feature is handled.

    Progress is shared through the append-only .scratch/progress.jsonl handoff log.
    Ralph validates each new record and marks its ticket complete.

.EXAMPLE
    Invoke-Ralph.ps1 -Agent codex

.EXAMPLE
    Invoke-Ralph.ps1 -Agent copilot -Iterations 5

.EXAMPLE
    Invoke-Ralph.ps1 -Agent codex -Feature watch-command

.EXAMPLE
    Invoke-Ralph.ps1 -Archive watch-command
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]
    $List,

    [Parameter()]
    [switch]
    $Cleanup,

    [Parameter()]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete)

        $scratch = Join-Path (Get-Location) '.scratch'
        if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
            return
        }

        Get-ChildItem -LiteralPath $scratch -Directory |
            Where-Object {
                $_.Name -cne 'done' -and
                (Test-Path -LiteralPath (
                    Join-Path $_.FullName 'spec.md'
                ) -PathType Leaf) -and
                $_.Name.StartsWith(
                    $wordToComplete,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            } |
            Sort-Object Name |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name,
                    $_.Name,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    $_.Name
                )
            }
    })]
    [ValidateNotNullOrEmpty()]
    [string]
    $Archive,

    [Parameter()]
    [ValidateSet('codex', 'copilot')]
    [string]
    $Agent = 'codex',

    [Parameter()]
    [string]
    $Model,

    [Parameter()]
    [string]
    $Effort,

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]
    $Iterations = 32,

    [Parameter()]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete)

        $scratch = Join-Path (Get-Location) '.scratch'
        if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
            return
        }

        Get-ChildItem -LiteralPath $scratch -Directory |
            Where-Object {
                $_.Name -cne 'done' -and
                (Test-Path -LiteralPath (
                    Join-Path $_.FullName 'spec.md'
                ) -PathType Leaf) -and
                $_.Name.StartsWith(
                    $wordToComplete,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            } |
            Sort-Object Name |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name,
                    $_.Name,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    $_.Name
                )
            }
    })]
    [ValidateNotNullOrEmpty()]
    [string]
    $Feature
)

function Invoke-NativeText {
    param(
        [Parameter(Mandatory)]
        [string]
        $FilePath,

        [Parameter()]
        [string[]]
        $ArgumentList = @()
    )

    $output = & $FilePath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "'$FilePath' failed with exit code $LASTEXITCODE.$([Environment]::NewLine)$message"
    }

    return ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
}

function Get-JsonPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object]
        $InputObject,

        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $value = $InputObject
    foreach ($segment in $Path -split '\.') {
        if ($null -eq $value) { return $null }
        $property = $value.PSObject.Properties[$segment]
        if ($null -eq $property) { return $null }
        $value = $property.Value
    }

    return $value
}

function Get-FirstJsonString {
    param(
        [Parameter(Mandatory)]
        [object]
        $InputObject,

        [Parameter(Mandatory)]
        [string[]]
        $Paths
    )

    foreach ($path in $Paths) {
        $value = Get-JsonPropertyValue -InputObject $InputObject -Path $path
        if ($null -ne $value -and -not [string]::IsNullOrEmpty([string]$value)) {
            return [string]$value
        }
    }

    return $null
}

function ConvertTo-NormalizedAgentMessage {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('codex', 'copilot')]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [object]
        $Event,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]
        $SeenMessageIds
    )

    if ($Name -eq 'codex') {
        if (
            $Event.type -ne 'item.completed' -or
            (Get-JsonPropertyValue -InputObject $Event -Path 'item.type') -ne 'agent_message'
        ) {
            return $null
        }

        $text = Get-FirstJsonString -InputObject $Event -Paths @('item.text')
        $eventId = Get-FirstJsonString -InputObject $Event -Paths @('id', 'event_id')
        $messageId = Get-FirstJsonString -InputObject $Event -Paths @(
            'item.id', 'item.message_id'
        )
        $agentInstanceId = Get-FirstJsonString -InputObject $Event -Paths @(
            'item.agent_instance_id', 'item.agent_id'
        )
    }
    else {
        if ($Event.type -ne 'assistant.message') { return $null }

        $text = Get-FirstJsonString -InputObject $Event -Paths @(
            'data.content', 'data.text', 'data.message.content', 'data.message.text',
            'content', 'text', 'message.content', 'message.text'
        )
        $eventId = Get-FirstJsonString -InputObject $Event -Paths @('id', 'event_id', 'eventId')
        $messageId = Get-FirstJsonString -InputObject $Event -Paths @(
            'data.message.id', 'data.message_id', 'data.messageId', 'data.id',
            'message.id', 'message_id', 'messageId'
        )
        $agentInstanceId = Get-FirstJsonString -InputObject $Event -Paths @(
            'data.agent_instance_id', 'data.agentInstanceId', 'data.agent_id',
            'data.agentId', 'agent_instance_id', 'agentInstanceId', 'agent_id', 'agentId'
        )
    }

    if ([string]::IsNullOrEmpty($text)) { return $null }
    foreach ($identity in @($eventId, $messageId) | Where-Object {
            -not [string]::IsNullOrEmpty($_)
        }) {
        if ($SeenMessageIds.Contains($identity)) { return $null }
    }
    foreach ($identity in @($eventId, $messageId) | Where-Object {
            -not [string]::IsNullOrEmpty($_)
        }) {
        [void]$SeenMessageIds.Add($identity)
    }

    return [pscustomobject]@{
        Text            = $text
        EventId         = $eventId
        MessageId       = $messageId
        AgentInstanceId = $agentInstanceId
    }
}

function Update-SubAgentLifecycle {
    param(
        [Parameter(Mandatory)]
        [object]
        $Event,

        [Parameter(Mandatory)]
        [hashtable]
        $DisplayNames
    )

    $eventType = Get-FirstJsonString -InputObject $Event -Paths @('type')
    if ($eventType -notmatch '(?i)(?:sub[_-]?agent|agent[._-]?lifecycle).*(?:start|create)|(?:start|create).*?(?:sub[_-]?agent|agent[._-]?lifecycle)') {
        return
    }

    $agentInstanceId = Get-FirstJsonString -InputObject $Event -Paths @(
        'data.agent_instance_id', 'data.agentInstanceId', 'data.agent_id', 'data.agentId',
        'agent_instance_id', 'agentInstanceId', 'agent_id', 'agentId'
    )
    $displayName = Get-FirstJsonString -InputObject $Event -Paths @(
        'data.display_name', 'data.displayName', 'data.name', 'display_name', 'displayName', 'name'
    )
    if (-not [string]::IsNullOrEmpty($agentInstanceId) -and
        -not [string]::IsNullOrEmpty($displayName)) {
        $DisplayNames[$agentInstanceId] = $displayName
    }
}

function ConvertFrom-SubduedHue {
    param(
        [Parameter(Mandatory)]
        [int]
        $Index
    )

    $hue = ($Index * 137.50776405003785) % 360
    $chroma = (1 - [Math]::Abs((2 * 0.62) - 1)) * 0.42
    $component = $chroma * (1 - [Math]::Abs((($hue / 60) % 2) - 1))
    $match = switch ([Math]::Floor($hue / 60)) {
        0 { @($chroma, $component, 0); break }
        1 { @($component, $chroma, 0); break }
        2 { @(0, $chroma, $component); break }
        3 { @(0, $component, $chroma); break }
        4 { @($component, 0, $chroma); break }
        default { @($chroma, 0, $component) }
    }
    $offset = 0.62 - ($chroma / 2)
    $rgb = $match | ForEach-Object { [int][Math]::Round(255 * ($_ + $offset)) }
    return "`e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
}

function Get-MarkdownInlineText {
    param(
        [Parameter(Mandatory)]
        [object]
        $Inlines,

        [Parameter(Mandatory)]
        [string]
        $Markdown,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $BaseStyle = '',

        [Parameter()]
        [switch]
        $Interactive
    )

    $reset = if ($Interactive) { $PSStyle.Reset } else { '' }
    $result = [System.Text.StringBuilder]::new()
    foreach ($inline in $Inlines) {
        $typeName = $inline.GetType().Name
        if ($typeName -eq 'LiteralInline') {
            [void]$result.Append([string]$inline.Content)
            continue
        }
        if ($typeName -eq 'HtmlInline') {
            [void]$result.Append([string]$inline.Tag)
            continue
        }
        if ($typeName -eq 'LineBreakInline') {
            [void]$result.Append("`n")
            continue
        }
        if ($typeName -eq 'LinkInline') {
            $label = Get-MarkdownInlineText -Inlines $inline -Markdown $Markdown `
                -BaseStyle $BaseStyle -Interactive:$Interactive
            $destination = [string]$inline.Url
            $isImage = [bool]$inline.IsImage
            if ($isImage) {
                $label = "Image: $label"
            }

            if (-not $Interactive) {
                [void]$result.Append($label)
                if (-not [string]::IsNullOrEmpty($destination) -and (
                        $isImage -or
                        $destination -cne $label
                    )) {
                    [void]$result.Append(" ($destination)")
                }
                continue
            }

            if ([string]::IsNullOrEmpty($destination)) {
                [void]$result.Append($label)
                continue
            }

            $osc8Prefix = "$([char]27)]8;;"
            $osc8Close = "$osc8Prefix$([char]27)\"
            [void]$result.Append("$osc8Prefix$destination$([char]27)\$label$osc8Close")
            continue
        }
        if ($typeName -eq 'CodeInline') {
            $content = [string]$inline.Content
            if ($Interactive) {
                [void]$result.Append("`e[7m $content ${reset}${BaseStyle}")
            }
            else {
                [void]$result.Append(" $content ")
            }
            continue
        }
        if ($typeName -eq 'EmphasisInline') {
            $start = [int]$inline.Span.Start
            $marker = if (($start + 2) -le $Markdown.Length) {
                $Markdown.Substring($start, 2)
            }
            elseif ($start -lt $Markdown.Length) {
                $Markdown.Substring($start, 1)
            }
            else {
                ''
            }
            $style = switch ($marker) {
                '**' { "`e[1m"; break }
                '__' { "`e[1m"; break }
                '~~' { "`e[9m"; break }
                default { "`e[3m" }
            }
            $content = Get-MarkdownInlineText -Inlines $inline -Markdown $Markdown `
                -BaseStyle $BaseStyle -Interactive:$Interactive
            if ($Interactive) {
                [void]$result.Append("$style$content${reset}${BaseStyle}")
            }
            else {
                [void]$result.Append($content)
            }
            continue
        }

        [void]$result.Append([string]$inline)
    }

    return $result.ToString()
}

function Get-RalphInlineMarkdown {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $BaseStyle,

        [Parameter()]
        [switch]
        $Interactive
    )

    $inlineDocument = ConvertFrom-Markdown -InputObject $Text -ErrorAction Stop
    $paragraph = @($inlineDocument.Tokens | Where-Object {
            $_.GetType().Name -eq 'ParagraphBlock'
        } | Select-Object -First 1)
    if ($paragraph.Count -eq 0) { return $Text }

    return Get-MarkdownInlineText -Inlines $paragraph[0].Inline -Markdown $Text `
        -BaseStyle $BaseStyle -Interactive:$Interactive
}

function ConvertTo-RalphListOrQuoteRows {
    param(
        [Parameter(Mandatory)]
        [string[]]
        $Lines,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $BaseStyle,

        [Parameter()]
        [switch]
        $Interactive
    )

    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($sourceLine in $Lines) {
        $line = $sourceLine
        $quotePrefix = ''
        while ($line -match '^\s*>\s?') {
            $quotePrefix += '│ '
            $line = $line -replace '^\s*>\s?', ''
        }

        if ($line -match '^(\s*)(?:[-+*]\s+|(\d+)[.)]\s+)(.*)$') {
            $indent = ' ' * (2 * [math]::Floor($matches[1].Length / 2))
            $marker = if ([string]::IsNullOrEmpty($matches[2])) { '• ' } else { "$($matches[2]). " }
            $content = $matches[3]
            if ($content -match '^\[([ xX])\]\s+(.*)$') {
                $taskState = $matches[1]
                $taskContent = $matches[2]
                $marker = if ($taskState -match '[xX]') { '[✓] ' } else { '[ ] ' }
                $content = $taskContent
            }
            $rendered = Get-RalphInlineMarkdown -Text $content -BaseStyle $BaseStyle `
                -Interactive:$Interactive
            $rows.Add("$quotePrefix$indent$marker$rendered")
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($quotePrefix)) {
            $rendered = Get-RalphInlineMarkdown -Text $line -BaseStyle $BaseStyle `
                -Interactive:$Interactive
            $rows.Add("$quotePrefix$rendered")
        }
    }

    return @($rows)
}

function Expand-RalphCodeTabs {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    $expanded = [System.Text.StringBuilder]::new()
    $column = 0
    $index = 0
    while ($index -lt $Text.Length) {
        if ($Text[$index] -eq "`t") {
            $spaces = 4 - ($column % 4)
            [void]$expanded.Append(' ' * $spaces)
            $column += $spaces
            $index++
            continue
        }

        $codePoint = [char]::ConvertToUtf32($Text, $index)
        $length = if ($codePoint -gt 0xFFFF) { 2 } else { 1 }
        $element = $Text.Substring($index, $length)
        [void]$expanded.Append($element)
        $column += Get-DisplayCellWidth -Text $element
        $index += $length
    }

    return $expanded.ToString()
}

function ConvertTo-RalphCodeRows {
    param(
        [Parameter(Mandatory)]
        [string]
        $Source,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $BaseStyle,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Language = '',

        [Parameter()]
        [switch]
        $Interactive
    )

    $sourceLines = @($Source -split '\r?\n')
    $language = $Language
    if ($sourceLines.Count -gt 0 -and $sourceLines[0] -match '^\s*(?:`{3,}|~{3,})\s*(\S*)') {
        $language = $matches[1]
        $sourceLines = @($sourceLines | Select-Object -Skip 1)
        if ($sourceLines.Count -gt 0 -and $sourceLines[-1] -match '^\s*(?:`{3,}|~{3,})\s*$') {
            $sourceLines = @($sourceLines | Select-Object -SkipLast 1)
        }
    }

    $rows = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrEmpty($language)) {
        $label = if ($Interactive) {
            "`e[2m$language$($PSStyle.Reset)$BaseStyle"
        }
        else {
            $language
        }
        $rows.Add($label)
    }
    foreach ($line in $sourceLines) {
        $codeRow = Expand-RalphCodeTabs -Text $line
        # This marker is consumed by the frame wrapper and never emitted to the terminal.
        $rows.Add("$(if ($Interactive) { [char]0x1E })$codeRow")
    }

    return @($rows)
}

function ConvertTo-RalphTableRows {
    param(
        [Parameter(Mandatory)]
        [object]
        $Table,

        [Parameter(Mandatory)]
        [string]
        $Markdown,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $BaseStyle,

        [Parameter()]
        [int]
        $InnerWidth = 0,

        [Parameter()]
        [switch]
        $Interactive
    )

    $columnCount = if ($Table.Count -gt 0) { [int]$Table[0].Count } else { 0 }
    if ($columnCount -eq 0) { return @() }

    $reset = if ($Interactive) { $PSStyle.Reset } else { '' }
    $headers = [System.Collections.Generic.List[string]]::new()
    $bodyRows = [System.Collections.Generic.List[string[]]]::new()
    $naturalWidths = @(for ($column = 0; $column -lt $columnCount; $column++) { 3 })
    foreach ($tableRow in $Table) {
        $cells = [string[]]::new($columnCount)
        for ($column = 0; $column -lt $columnCount; $column++) {
            $cell = if ($column -lt $tableRow.Count) { $tableRow[$column] } else { $null }
            $content = if ($null -eq $cell) {
                ''
            }
            else {
                Get-MarkdownInlineText -Inlines $cell.Inline -Markdown $Markdown `
                    -BaseStyle $BaseStyle -Interactive:$Interactive
            }
            $cells[$column] = $content
            $naturalWidths[$column] = [Math]::Max(
                $naturalWidths[$column],
                (Get-DisplayCellWidth -Text $content)
            )
        }
        if ($tableRow.IsHeader) {
            foreach ($cell in $cells) { $headers.Add($cell) }
        }
        else {
            $bodyRows.Add($cells)
        }
    }
    if ($headers.Count -eq 0) { return @() }

    # A bordered row needs three cells per column plus its two outer borders.
    $minimumWidth = (5 * $columnCount) + 1
    if ($InnerWidth -gt 0 -and $InnerWidth -lt $minimumWidth) {
        $verticalRows = [System.Collections.Generic.List[string]]::new()
        foreach ($body in $bodyRows) {
            for ($column = 0; $column -lt $columnCount; $column++) {
                $verticalRows.Add("$BaseStyle$($headers[$column]): $($body[$column])${reset}")
            }
        }
        return @($verticalRows)
    }

    $widths = [int[]]$naturalWidths.Clone()
    if ($InnerWidth -gt 0) {
        $availableContentWidth = $InnerWidth - ((3 * $columnCount) + 1)
        while (($widths | Measure-Object -Sum).Sum -gt $availableContentWidth) {
            $widest = 0
            for ($column = 1; $column -lt $columnCount; $column++) {
                if ($widths[$column] -gt $widths[$widest]) { $widest = $column }
            }
            if ($widths[$widest] -le 3) { break }
            $widths[$widest]--
        }
    }

    $alignments = @(
        for ($column = 0; $column -lt $columnCount; $column++) {
            if ($column -lt $Table.ColumnDefinitions.Count) {
                [string]$Table.ColumnDefinitions[$column].Alignment
            }
            else {
                'Left'
            }
        }
    )
    $formatCell = {
        param([string] $Content, [int] $Width, [string] $Alignment)
        $padding = [Math]::Max(0, $Width - (Get-DisplayCellWidth -Text $Content))
        switch ($Alignment) {
            'Right' { return (' ' * $padding) + $Content }
            'Center' {
                $left = [Math]::Floor($padding / 2)
                return (' ' * $left) + $Content + (' ' * ($padding - $left))
            }
            default { return $Content + (' ' * $padding) }
        }
    }
    $renderRow = {
        param([string[]] $Cells)
        $wrappedCells = [System.Collections.Generic.List[object[]]]::new()
        $rowCount = 1
        for ($column = 0; $column -lt $columnCount; $column++) {
            $wrapped = @(Split-AgentOutputContent -Content $Cells[$column] -InnerWidth $widths[$column])
            if ($wrapped.Count -eq 0) { $wrapped = @([pscustomobject]@{ Text = ''; Width = 0 }) }
            $wrappedCells.Add($wrapped)
            $rowCount = [Math]::Max($rowCount, $wrapped.Count)
        }
        $renderedRows = [System.Collections.Generic.List[string]]::new()
        for ($row = 0; $row -lt $rowCount; $row++) {
            $parts = for ($column = 0; $column -lt $columnCount; $column++) {
                $content = if ($row -lt $wrappedCells[$column].Count) {
                    [string]$wrappedCells[$column][$row].Text
                }
                else {
                    ''
                }
                & $formatCell $content $widths[$column] $alignments[$column]
            }
            $renderedRows.Add("$BaseStyle| $($parts -join ' | ') |${reset}")
        }
        return @($renderedRows)
    }

    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($row in @(& $renderRow $headers.ToArray())) { $rows.Add($row) }
    $separator = for ($column = 0; $column -lt $columnCount; $column++) { '─' * $widths[$column] }
    $rows.Add("$BaseStyle|$($separator -join '┼')|${reset}")
    foreach ($body in $bodyRows) {
        foreach ($row in @(& $renderRow $body)) { $rows.Add($row) }
    }
    return @($rows)
}

function ConvertTo-RalphMarkdown {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Markdown,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $BaseStyle = '',

        [Parameter()]
        [switch]
        $Interactive,

        [Parameter()]
        [int]
        $InnerWidth = 0
    )

    $baseStyle = if ($Interactive) {
        if ([string]::IsNullOrEmpty($BaseStyle)) { "`e[38;5;252m" } else { $BaseStyle }
    }
    else { '' }
    $reset = if ($Interactive) { $PSStyle.Reset } else { '' }
    # Markdig treats an ESC sequence as Markdown punctuation. Preserve valid message
    # controls verbatim rather than letting parsing alter their byte sequence.
    if ($Markdown.Contains([string][char]27)) {
        return $Markdown.Trim("`r", "`n")
    }
    try {
        $document = ConvertFrom-Markdown -InputObject $Markdown -ErrorAction Stop
        $rows = [System.Collections.Generic.List[string]]::new()
        $sourceLines = @($Markdown -split '\r?\n')
        $structuralLines = @($sourceLines | Where-Object {
                $_ -match '^\s*(?:[-+*]\s+|\d+[.)]\s+|>+)'
            })
        if ($structuralLines.Count -eq @($sourceLines | Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }).Count -and $structuralLines.Count -gt 0) {
            $structuralRows = ConvertTo-RalphListOrQuoteRows -Lines $sourceLines `
                -BaseStyle $baseStyle -Interactive:$Interactive
            return (($structuralRows | ForEach-Object {
                        "$baseStyle$_${reset}"
                    }) -join "`n").Trim("`r", "`n")
        }
        foreach ($block in $document.Tokens) {
            $typeName = $block.GetType().Name
            if ($typeName -eq 'Table') {
                $tableRows = ConvertTo-RalphTableRows -Table $block -Markdown $Markdown `
                    -BaseStyle $baseStyle -InnerWidth $InnerWidth -Interactive:$Interactive
                if ($tableRows.Count -gt 0) {
                    if ($rows.Count -gt 0) { $rows.Add('') }
                    foreach ($tableRow in $tableRows) { $rows.Add($tableRow) }
                }
                continue
            }
            if ($typeName -match 'CodeBlock$') {
                $start = [Math]::Max(0, [int]$block.Span.Start)
                $length = [Math]::Min(
                    $Markdown.Length - $start,
                    ([int]$block.Span.End - $start + 1)
                )
                $declaredLanguage = if ($null -ne $block.PSObject.Properties['Info']) {
                    [string]$block.Info
                }
                else {
                    ''
                }
                $codeRows = ConvertTo-RalphCodeRows -Source $Markdown.Substring($start, $length) `
                    -BaseStyle $baseStyle -Language $declaredLanguage -Interactive:$Interactive
                if ($rows.Count -gt 0) { $rows.Add('') }
                foreach ($codeRow in $codeRows) {
                    $marker = if ($Interactive -and $codeRow.StartsWith(
                            [string][char]0x1E,
                            [System.StringComparison]::Ordinal
                        )) {
                        [string][char]0x1E
                    }
                    else {
                        ''
                    }
                    if ($marker) { $codeRow = $codeRow.Substring(1) }
                    $rows.Add("$marker$baseStyle$codeRow${reset}")
                }
                continue
            }
            if ($typeName -match 'ThematicBreak') {
                if ($rows.Count -gt 0) { $rows.Add('') }
                $rows.Add("$baseStyle$('─' * 12)${reset}")
                continue
            }
            if ($typeName -match 'Html') {
                $start = [Math]::Max(0, [int]$block.Span.Start)
                $length = [Math]::Min(
                    $Markdown.Length - $start,
                    ([int]$block.Span.End - $start + 1)
                )
                if ($rows.Count -gt 0) { $rows.Add('') }
                foreach ($htmlRow in @($Markdown.Substring($start, $length) -split '\r?\n')) {
                    $rows.Add("$baseStyle$htmlRow${reset}")
                }
                continue
            }
            if ($typeName -in @('ListBlock', 'QuoteBlock')) {
                $start = [Math]::Max(0, [int]$block.Span.Start)
                $length = [Math]::Min(
                    $Markdown.Length - $start,
                    ([int]$block.Span.End - $start + 1)
                )
                $blockSource = $Markdown.Substring($start, $length)
                $structuralRows = ConvertTo-RalphListOrQuoteRows `
                    -Lines @($blockSource -split '\r?\n') `
                    -BaseStyle $baseStyle -Interactive:$Interactive
                if ($structuralRows.Count -gt 0) {
                    if ($rows.Count -gt 0) { $rows.Add('') }
                    foreach ($structuralRow in $structuralRows) {
                        $rows.Add("$baseStyle$structuralRow${reset}")
                    }
                }
                continue
            }
            if ($typeName -notin @('HeadingBlock', 'ParagraphBlock')) { continue }

            $content = Get-MarkdownInlineText -Inlines $block.Inline -Markdown $Markdown `
                -BaseStyle $baseStyle -Interactive:$Interactive
            if ($typeName -eq 'HeadingBlock') {
                $level = [int]$block.Level
                if ($level -eq 1) {
                    if ($Interactive) {
                        $content = "`e[1;7m $content ${reset}${baseStyle}"
                    }
                    else {
                        $content = "# $content"
                    }
                }
                else {
                    $content = ('#' * $level) + " $content"
                    if ($Interactive -and $level -lt 6) {
                        $content = "`e[1m$content${reset}${baseStyle}"
                    }
                }
            }
            if ($rows.Count -gt 0) { $rows.Add('') }
            $rows.Add("$baseStyle$content${reset}")
        }

        return ($rows -join "`n").Trim("`r", "`n")
    }
    catch {
        return $Markdown.Trim("`r", "`n")
    }
}

function Invoke-Agent {
    param(
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [string]
        $CommandPath,

        [Parameter(Mandatory)]
        [string]
        $Prompt,

        [Parameter(Mandatory)]
        [string]
        $Model,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Effort,

        [Parameter()]
        [int]
        $FrameInnerWidth = 0,

        [Parameter()]
        [hashtable]
        $WorkboardState,

        [Parameter()]
        [string]
        $ScratchDirectory
    )

    $arguments = switch ($Name) {
        'codex' {
            @(
                'exec',
                '--json',
                '--model', $Model,
                '--config', "model_reasoning_effort=`"$Effort`"",
                '--sandbox', 'workspace-write',
                $Prompt
            )
        }
        'copilot' {
            $copilotArguments = @(
                "--log-level", "debug",
                '--model', $Model,
                '--output-format', 'json',
                '--stream', 'off'
            )
            if (-not [string]::IsNullOrEmpty($Effort)) {
                $copilotArguments += @('--effort', $Effort)
            }
            $copilotArguments += @(
                '-s',
                '--allow-tool=read,write,shell',
                '-p', $Prompt
            )
            $copilotArguments
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $seenMessageIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $subAgentDisplayNames = @{}
    $subAgentStyles = @{}
    $outputState = [pscustomobject]@{
        HasEmittedNonBlank = $false
        LastWasBlank = $false
    }
    $hasCompletedMessage = $false
    & $CommandPath @arguments 2>&1 |
        ForEach-Object {
            $rawLine = $_.ToString()
            $lines.Add($rawLine)
            $text = $null
            try {
                $event = $rawLine | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                if (-not [string]::IsNullOrEmpty($rawLine)) {
                    $text = $rawLine
                }
                $event = $null
            }
            if ($null -ne $event) {
                if ($Name -eq 'copilot') {
                    Update-SubAgentLifecycle -Event $event -DisplayNames $subAgentDisplayNames
                }
                $message = ConvertTo-NormalizedAgentMessage `
                    -Name $Name `
                    -Event $event `
                    -SeenMessageIds $seenMessageIds
                if ($null -ne $message) {
                    $isSubAgent = -not [string]::IsNullOrEmpty($message.AgentInstanceId)
                    $baseStyle = ''
                    $label = ''
                    if ($isSubAgent) {
                        $agentInstanceId = $message.AgentInstanceId
                        if (-not $subAgentStyles.ContainsKey($agentInstanceId)) {
                            $subAgentStyles[$agentInstanceId] = ConvertFrom-SubduedHue `
                                -Index $subAgentStyles.Count
                        }
                        $baseStyle = [string]$subAgentStyles[$agentInstanceId]
                        $displayName = if ($subAgentDisplayNames.ContainsKey($agentInstanceId)) {
                            [string]$subAgentDisplayNames[$agentInstanceId]
                        }
                        else {
                            'Sub-agent'
                        }
                        $label = if ($WorkboardState) {
                            "${baseStyle}`e[1m${displayName}:$($PSStyle.Reset)$baseStyle"
                        }
                        else {
                            "${displayName}:"
                        }
                    }
                    if ($WorkboardState) {
                        Refresh-RalphWorkboardForResize `
                            -ScratchDirectory $ScratchDirectory `
                            -State $WorkboardState | Out-Null
                    }
                    $rendered = ConvertTo-RalphMarkdown -Markdown $message.Text `
                        -BaseStyle $baseStyle `
                        -Interactive:([bool]$WorkboardState) `
                        -InnerWidth $(if ($WorkboardState) {
                            [int]$WorkboardState.InnerWidth
                        }
                        else {
                            $FrameInnerWidth
                        })
                    if (-not [string]::IsNullOrEmpty($label)) {
                        $rendered = "$label`n$rendered"
                    }
                    $text = if ($hasCompletedMessage) {
                        "`n$rendered"
                    }
                    else {
                        $rendered
                    }
                    $hasCompletedMessage = $true
                }
            }

            if ($null -ne $text) {
                if ($WorkboardState) {
                    Refresh-RalphWorkboardForResize `
                        -ScratchDirectory $ScratchDirectory `
                        -State $WorkboardState | Out-Null
                    $rows = Split-AgentOutputContent -Content ([string]$text) `
                        -InnerWidth ([int]$WorkboardState.InnerWidth)
                    foreach ($row in $rows) {
                        Write-TypedAgentOutputRow -Content $row.Text `
                            -ContentWidth ([int]$row.Width) `
                            -InnerWidth ([int]$WorkboardState.InnerWidth) `
                            -WorkboardState $WorkboardState
                    }
                }
                else {
                    foreach ($outputLine in ([string]$text -split '\r?\n')) {
                        $isBlank = [string]::IsNullOrWhiteSpace($outputLine)
                        if ($isBlank -and (
                            -not $outputState.HasEmittedNonBlank -or
                            $outputState.LastWasBlank
                        )) {
                            continue
                        }

                        $displayLine = if ($isBlank) { '' } else { $outputLine }
                        if ($FrameInnerWidth -gt 0) {
                            Write-AgentOutputRow -Content $displayLine -InnerWidth $FrameInnerWidth
                        }
                        else {
                            Write-Host $displayLine
                        }

                        if (-not $isBlank) { $outputState.HasEmittedNonBlank = $true }
                        $outputState.LastWasBlank = $isBlank
                    }
                }
            }
        }

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }

    return $lines -join [Environment]::NewLine
}

function Get-NewProgressEntry {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Before,

        [Parameter(Mandatory)]
        [string]
        $After
    )

    if (-not $After.StartsWith($Before, [System.StringComparison]::Ordinal)) {
        throw 'The iteration must only append to .scratch/progress.jsonl.'
    }

    if ($Before.Length -gt 0 -and -not $Before.EndsWith(
        "`n",
        [System.StringComparison]::Ordinal
    )) {
        throw '.scratch/progress.jsonl must end with a newline before appending a record.'
    }

    $appendedContent = $After.Substring($Before.Length)
    $lines = @($appendedContent -split '\r?\n' | Where-Object { $_.Length -gt 0 })
    if ($lines.Count -ne 1) {
        throw 'The iteration must append exactly one JSONL record to .scratch/progress.jsonl.'
    }

    try {
        $entry = $lines[0] | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The appended progress record is not valid JSON: $($_.Exception.Message)"
    }

    $properties = @($entry.PSObject.Properties.Name)
    foreach ($required in 'feature', 'ticket', 'changes', 'checks') {
        if ($properties -cnotcontains $required -or
            $entry.$required -isnot [string] -or
            [string]::IsNullOrWhiteSpace($entry.$required)) {
            throw "The appended progress record requires a non-empty string '$required' field."
        }
    }

    return $entry
}

function Repair-ProgressHistoryTerminator {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $content = [System.IO.File]::ReadAllBytes($Path)
    if ($content.Length -eq 0 -or $content[$content.Length - 1] -eq [byte]10) {
        return $false
    }

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    )
    try {
        $stream.WriteByte([byte]10)
    }
    finally {
        $stream.Dispose()
    }

    return $true
}

function Assert-ProgressEntryMatchesScope {
    param(
        [Parameter(Mandatory)]
        [psobject]
        $ProgressEntry,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $ScopeFeature = '',

        [Parameter(Mandatory)]
        [ValidateSet('automatic', 'feature')]
        [string]
        $ScopeKind
    )

    if ($ScopeKind -ne 'automatic' -and $ProgressEntry.feature -cne $ScopeFeature) {
        throw "Progress record does not match requested feature '$ScopeFeature'."
    }

    return $ProgressEntry
}

function Get-TrackerStatusPattern {
    return '^\s*(?:(?:>\s*)|(?:[-+*]\s+))*(?:Status\s*:|\*\*Status\s*:\*\*|\*\*Status\*\*\s*:)\s*(.*?)\s*$'
}

function Get-MarkdownLinesOutsideFencedCode {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $content = [System.IO.File]::ReadAllText($Path)
    $fencePattern = [regex]::new('^\s*(```|~~~)')
    $inFence = $false
    foreach ($lineMatch in [regex]::Matches(
        $content,
        '^.*$',
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )) {
        $line = $lineMatch.Value
        if ($fencePattern.IsMatch([string]$line)) {
            $inFence = -not $inFence
            continue
        }
        if (-not $inFence) {
            [pscustomobject]@{
                Text       = $line
                StartIndex = $lineMatch.Index
            }
        }
    }
}

function Get-TrackerBlockedByPattern {
    return '^\s*(?:(?:>\s*)|(?:[-+*]\s+))*(?:Blocked by\s*:|\*\*Blocked by\s*:\*\*|\*\*Blocked by\*\*\s*:)\s*(.*?)\s*$'
}

function Get-TrackerComparableTitle {
    param(
        [Parameter(Mandatory)]
        [string]
        $Title
    )

    return [regex]::Replace($Title.Trim(), '\.$', '')
}

function Set-TrackerTicketStatus {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $ExpectedStatus,

        [Parameter(Mandatory)]
        [ValidateSet('ready-for-agent', 'done', 'closed')]
        [string]
        $Status
    )

    if ((Get-TrackerTicketStatus -Path $Path) -cne $ExpectedStatus) {
        throw "Tracker ticket does not have expected Status '$ExpectedStatus': $Path"
    }

    $statusPattern = [regex]::new(
        (Get-TrackerStatusPattern),
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Multiline
    )
    $content = [System.IO.File]::ReadAllText($Path)
    foreach ($line in (Get-MarkdownLinesOutsideFencedCode -Path $Path)) {
        $match = $statusPattern.Match([string]$line.Text)
        if ($match.Success) {
            $valueIndex = $line.StartIndex + $match.Groups[1].Index
            $updated = $content.Remove(
                $valueIndex,
                $match.Groups[1].Length
            ).Insert($valueIndex, $Status)
            [System.IO.File]::WriteAllText($Path, $updated)
            return
        }
    }

    throw "Validated Status declaration was not found: $Path"
}

function Get-TrackerBlockedByReferences {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $pattern = [regex]::new(
        (Get-TrackerBlockedByPattern),
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $matches = [System.Collections.Generic.List[System.Text.RegularExpressions.Match]]::new()
    foreach ($line in (Get-MarkdownLinesOutsideFencedCode -Path $Path)) {
        $match = $pattern.Match([string]$line.Text)
        if ($match.Success) {
            $matches.Add($match)
        }
    }

    if ($matches.Count -ne 1) {
        throw "Tracker ticket must have exactly one Blocked by declaration: $Path"
    }

    $value = $matches[0].Groups[1].Value.Trim()
    if ($value -match '(?i)^none(?:\s+[—-]\s+.+)?$') {
        return @()
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Tracker ticket has malformed Blocked by declaration: $Path"
    }

    $references = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($reference in ($value -split ';')) {
        $reference = $reference.Trim()
        $match = [regex]::Match($reference, '^(\d+)(?:\s*[—-]\s*(.+?))?$')
        if (-not $match.Success) {
            throw "Tracker ticket has malformed Blocked by reference '$reference': $Path"
        }
        $references.Add([pscustomobject]@{
            Id    = $match.Groups[1].Value
            Title = $match.Groups[2].Value.Trim()
        })
    }

    return @($references)
}

function Invoke-TrackerDependencyReconciliation {
    param(
        [Parameter(Mandatory)]
        [string]
        $FeatureDirectory
    )

    $issuesDirectory = Join-Path $FeatureDirectory 'issues'
    if (-not (Test-Path -LiteralPath $issuesDirectory -PathType Container)) {
        throw "Feature issues directory not found: $issuesDirectory"
    }

    $ticketsById = @{}
    foreach ($ticket in (Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
            Sort-Object Name)) {
        $idMatch = [regex]::Match($ticket.BaseName, '^(\d+)(?:[._-]|$)')
        if (-not $idMatch.Success) {
            throw "Tracker ticket has no leading identifier: $($ticket.FullName)"
        }
        $id = $idMatch.Groups[1].Value
        if ($ticketsById.ContainsKey($id)) {
            throw "Feature has duplicate ticket identifier '$id': $FeatureDirectory"
        }
        $heading = Get-MarkdownHeading -Path $ticket.FullName -Fallback $ticket.BaseName
        $title = [regex]::Replace($heading, '^\d+\s*[—-]\s*', '').Trim()
        $ticketsById[$id] = [pscustomobject]@{
            Id           = $id
            File         = $ticket
            Title        = $title
            Status       = Get-TrackerTicketStatus -Path $ticket.FullName
            Dependencies = @()
        }
    }

    foreach ($ticket in $ticketsById.Values) {
        $dependencies = [System.Collections.Generic.List[string]]::new()
        foreach ($reference in (Get-TrackerBlockedByReferences -Path $ticket.File.FullName)) {
            if (-not $ticketsById.ContainsKey($reference.Id)) {
                throw "Tracker ticket '$($ticket.Id)' has unknown Blocked by reference '$($reference.Id)': $($ticket.File.FullName)"
            }
            $dependency = $ticketsById[$reference.Id]
            if (-not [string]::IsNullOrWhiteSpace($reference.Title) -and
                (Get-TrackerComparableTitle -Title $reference.Title) -cne
                    (Get-TrackerComparableTitle -Title $dependency.Title)) {
                throw "Tracker ticket '$($ticket.Id)' has mismatched Blocked by title for '$($reference.Id)': $($ticket.File.FullName)"
            }
            if (-not $dependencies.Contains($dependency.Id)) {
                $dependencies.Add($dependency.Id)
            }
        }
        $ticket.Dependencies = @($dependencies)
    }

    $visitStates = @{}
    $visitPath = [System.Collections.Generic.List[string]]::new()
    $visit = $null
    $visit = {
        param([string] $TicketId)
        $state = if ($visitStates.ContainsKey($TicketId)) { $visitStates[$TicketId] } else { '' }
        if ($state -eq 'visiting') {
            $start = $visitPath.IndexOf($TicketId)
            $cycle = @($visitPath.GetRange($start, $visitPath.Count - $start)) + $TicketId
            throw "Tracker dependency cycle: $($cycle -join ' -> ')"
        }
        if ($state -eq 'visited') { return }

        $visitStates[$TicketId] = 'visiting'
        $visitPath.Add($TicketId)
        foreach ($dependencyId in $ticketsById[$TicketId].Dependencies) {
            & $visit $dependencyId
        }
        $visitPath.RemoveAt($visitPath.Count - 1)
        $visitStates[$TicketId] = 'visited'
    }
    foreach ($ticketId in @($ticketsById.Keys | Sort-Object)) {
        & $visit $ticketId
    }

    $completedIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $markCompletedDependencies = $null
    $markCompletedDependencies = {
        param([string] $TicketId)
        if (-not $completedIds.Add($TicketId)) { return }
        foreach ($dependencyId in $ticketsById[$TicketId].Dependencies) {
            & $markCompletedDependencies $dependencyId
        }
    }
    foreach ($ticket in $ticketsById.Values | Where-Object {
            $_.Status -in @('done', 'closed')
        }) {
        & $markCompletedDependencies $ticket.Id
    }

    $updatedIds = [System.Collections.Generic.List[string]]::new()
    foreach ($ticketId in @($completedIds | Sort-Object)) {
        $ticket = $ticketsById[$ticketId]
        if ($ticket.Status -ceq 'ready-for-agent') {
            Set-TrackerTicketStatus -Path $ticket.File.FullName -ExpectedStatus 'ready-for-agent' -Status 'done'
            $updatedIds.Add($ticketId)
        }
    }

    return [pscustomobject]@{
        CompletedTicketIds = @($completedIds | Sort-Object)
        UpdatedTicketIds   = @($updatedIds)
    }
}

function Complete-TrackerTicket {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [psobject]
        $ProgressEntry
    )

    if ($ProgressEntry.feature -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Unsafe feature slug in progress record: '$($ProgressEntry.feature)'."
    }
    if ($ProgressEntry.ticket -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') {
        throw "Unsafe ticket id in progress record: '$($ProgressEntry.ticket)'."
    }

    $issuesDirectory = Join-Path (
        Join-Path $ScratchDirectory $ProgressEntry.feature
    ) 'issues'
    if (-not (Test-Path -LiteralPath $issuesDirectory -PathType Container)) {
        throw "Active feature issues directory not found: $issuesDirectory"
    }

    $ticketName = $ProgressEntry.ticket
    if ($ticketName.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        $ticketName = $ticketName.Substring(0, $ticketName.Length - 3)
    }

    $tickets = @(
        Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
            Where-Object { $_.BaseName -ceq $ticketName }
    )
    if ($tickets.Count -ne 1) {
        throw "Unfinished tracker ticket not found: $($ProgressEntry.feature)/$ticketName"
    }

    $ticket = $tickets[0]
    $status = Get-TrackerTicketStatus -Path $ticket.FullName
    if ($status -cne 'ready-for-agent') {
        throw "Ticket is already completed: $($ProgressEntry.feature)/$ticketName"
    }

    Set-TrackerTicketStatus -Path $ticket.FullName -ExpectedStatus 'ready-for-agent' -Status 'done'
    return $ticketName
}

function Move-CompletedTrackerFeature {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [string]
        $Feature,

        [Parameter()]
        [switch]
        $AllowUnfinished
    )

    $featureDirectory = Join-Path $ScratchDirectory $Feature
    $issuesDirectory = Join-Path $featureDirectory 'issues'
    $unfinishedTickets = @(
        Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
            Where-Object {
                (Get-TrackerTicketStatus -Path $_.FullName) -ceq 'ready-for-agent'
            }
    )
    if (-not $AllowUnfinished -and $unfinishedTickets.Count -gt 0) {
        return $null
    }

    $doneDirectory = Join-Path $ScratchDirectory 'done'
    if (-not (Test-Path -LiteralPath $doneDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $doneDirectory | Out-Null
    }

    $archiveName = $Feature
    $suffix = 2
    while (Test-Path -LiteralPath (
        Join-Path $doneDirectory $archiveName
    )) {
        $archiveName = "$Feature-$suffix"
        $suffix++
    }

    $archivePath = Join-Path $doneDirectory $archiveName
    Move-Item -LiteralPath $featureDirectory -Destination $archivePath
    return $archivePath
}

function Get-TrackerTicketStatus {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $statusPattern = [regex]::new((Get-TrackerStatusPattern), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $statusLikePattern = [regex]::new('^\s*(?:(?:>\s*)|(?:[-+*]\s+))*(?:\*\*)?Status(?:\*\*)?\s*[:=]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $statusMatches = [System.Collections.Generic.List[System.Text.RegularExpressions.Match]]::new()
    $malformed = $false

    foreach ($line in (Get-MarkdownLinesOutsideFencedCode -Path $Path)) {
        $match = $statusPattern.Match([string]$line.Text)
        if ($match.Success) {
            $statusMatches.Add($match)
        }
        elseif ($statusLikePattern.IsMatch([string]$line.Text)) {
            $malformed = $true
        }
    }

    if ($malformed) {
        throw "Tracker ticket has malformed Status: $Path"
    }
    if ($statusMatches.Count -eq 0) {
        throw "Tracker ticket is missing Status: $Path"
    }
    if ($statusMatches.Count -ne 1) {
        throw "Tracker ticket must have exactly one Status: $Path"
    }

    $status = $statusMatches[0].Groups[1].Value.Trim().ToLowerInvariant()
    if ($status -notin @('ready-for-agent', 'done', 'closed')) {
        throw "Tracker ticket has unsupported Status '$status': $Path"
    }

    return $status
}

function Get-UnfinishedTrackerTickets {
    param(
        [Parameter(Mandatory)]
        [string]
        $FeatureDirectory
    )

    $issuesDirectory = Join-Path $FeatureDirectory 'issues'
    if (-not (Test-Path -LiteralPath $issuesDirectory -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
            Where-Object {
                (Get-TrackerTicketStatus -Path $_.FullName) -ceq 'ready-for-agent'
            }
    )
}

function Get-ActiveTrackerFeatures {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory
    )

    return @(
        Get-TrackerFeatureDirectories -ScratchDirectory $ScratchDirectory |
            Where-Object {
                @(Get-UnfinishedTrackerTickets -FeatureDirectory $_.FullName).Count -gt 0
            }
    )
}

function Get-TrackerFeatureDirectories {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory
    )

    return @(
        Get-ChildItem -LiteralPath $ScratchDirectory -Directory |
            Where-Object {
                $_.Name -cne 'done' -and
                (Test-Path -LiteralPath (
                    Join-Path $_.FullName 'spec.md'
                ) -PathType Leaf)
            } |
            Sort-Object Name
    )
}

function Get-MarkdownHeading {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Fallback
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $Fallback
    }

    $match = [regex]::Match(
        [System.IO.File]::ReadAllText($Path),
        '(?m)^#\s+(.+?)\s*$'
    )
    if (-not $match.Success) {
        return $Fallback
    }

    return $match.Groups[1].Value
}

function Get-NaturalSortKey {
    param(
        [Parameter(Mandatory)]
        [string]
        $Value
    )

    return [regex]::Replace(
        $Value.ToLowerInvariant(),
        '\d+',
        { param($match) $match.Value.PadLeft(20, '0') }
    )
}

function Format-TrackerMetadataRow {
    param(
        [Parameter(Mandatory)]
        [string]
        $Label,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Value
    )

    $muted = $PSStyle.Foreground.BrightBlack
    $valueColor = $PSStyle.Foreground.BrightWhite
    $reset = $PSStyle.Reset
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = '-'
    }

    return "${muted}${Label}:${reset} ${valueColor}${Value}${reset}"
}

function Format-TrackerHeaderRow {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Repository = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $AgentSummary = '',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $InnerWidth = 0
    )

    $repositoryText = Format-TrackerMetadataRow -Label 'Repository' -Value $Repository
    if ([string]::IsNullOrWhiteSpace($AgentSummary)) {
        return $repositoryText
    }

    $dimAgent = "`e[2;38;5;8m${AgentSummary}$($PSStyle.Reset)"
    $gap = 2
    if ($InnerWidth -gt 0) {
        $gap = [Math]::Max(
            2,
            $InnerWidth -
                (Get-DisplayCellWidth -Text $repositoryText) -
                (Get-DisplayCellWidth -Text $dimAgent)
        )
    }

    return "$repositoryText$(' ' * $gap)$dimAgent"
}

function Get-TrackerLines {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        # Feature directory names that were active at startup and must remain
        # visible after they complete and are archived.
        [Parameter()]
        [string[]]
        $RetainedFeatureNames = @(),

        # When set, render only these feature directory names. This keeps a
        # selected-feature workboard focused while allowing automatic runs to
        # continue showing every active feature.
        [Parameter()]
        [string[]]
        $DisplayFeatureNames = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Repository = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $AgentSummary = '',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $InnerWidth = 0,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $CurrentIteration = 0,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $TotalIterations = 0,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $CompletedIterations = 0,

        [Parameter()]
        [bool]
        $IncludeIteration = $true
    )

    $displayFeatureNameSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($displayFeatureName in $DisplayFeatureNames) {
        if (-not [string]::IsNullOrWhiteSpace($displayFeatureName)) {
            [void] $displayFeatureNameSet.Add($displayFeatureName)
        }
    }

    $activeFeatureNameSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $activeFeatures = @(
        Get-ChildItem -LiteralPath $ScratchDirectory -Directory |
            Where-Object {
                $_.Name -cne 'done' -and
                ($displayFeatureNameSet.Count -eq 0 -or
                    $displayFeatureNameSet.Contains($_.Name))
            } |
            ForEach-Object {
                [void] $activeFeatureNameSet.Add($_.Name)
                $_
            } |
            Sort-Object { $_.Name.ToLowerInvariant() }
    )

    # Find retained features that have since been archived into done/.
    $doneDirectory = Join-Path $ScratchDirectory 'done'
    $displayEntries = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($f in $activeFeatures) {
        $displayEntries.Add([pscustomobject]@{
            Directory   = $f
            DisplayName = $f.Name
            IsRetained  = $false
        })
    }
    foreach ($retainedName in $RetainedFeatureNames) {
        if ($activeFeatureNameSet.Contains($retainedName)) { continue }
        if (-not (Test-Path -LiteralPath $doneDirectory -PathType Container)) { continue }
        $archivedDir = @(
            Get-ChildItem -LiteralPath $doneDirectory -Directory |
                Where-Object {
                    $_.Name -ceq $retainedName -or
                    $_.Name -cmatch ('^' + [regex]::Escape($retainedName) + '-\d+$')
                } |
                Sort-Object Name
        ) | Select-Object -First 1
        if ($archivedDir) {
            $displayEntries.Add([pscustomobject]@{
                Directory   = $archivedDir
                DisplayName = $retainedName
                IsRetained  = $true
            })
        }
    }
    $features = @($displayEntries | Sort-Object { $_.DisplayName.ToLowerInvariant() })

    $featureRows = [System.Collections.Generic.List[object]]::new()
    $unfinishedCount = 0
    foreach ($entry in $features) {
        $featureDir = $entry.Directory
        $issuesDirectory = Join-Path $featureDir.FullName 'issues'
        $tickets = @(
            if (Test-Path -LiteralPath $issuesDirectory -PathType Container) {
                Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
                    ForEach-Object {
                        $status = Get-TrackerTicketStatus -Path $_.FullName
                        $completed = $entry.IsRetained -or $status -in @('done', 'closed')
                        [pscustomobject]@{
                            File      = $_
                            Completed = $completed
                            SortKey   = Get-NaturalSortKey -Value $_.Name
                        }
                    } |
                    Sort-Object SortKey
            }
        )
        $unfinishedCount += @($tickets | Where-Object { -not $_.Completed }).Count
        $featureRows.Add([pscustomobject]@{
            Directory = $featureDir
            Heading   = Get-MarkdownHeading `
                -Path (Join-Path $featureDir.FullName 'spec.md') `
                -Fallback $entry.DisplayName
            Tickets   = $tickets
        })
    }

    $accent  = $PSStyle.Foreground.BrightCyan
    $muted   = $PSStyle.Foreground.BrightBlack
    $success = $PSStyle.Foreground.BrightGreen
    $reset   = $PSStyle.Reset

    $cappedTotal = if ($TotalIterations -gt 0 -and $CurrentIteration -gt 0) {
        [Math]::Min($TotalIterations, $CompletedIterations + $unfinishedCount)
    } else { 0 }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add((Format-TrackerHeaderRow -Repository $Repository `
        -AgentSummary $AgentSummary -InnerWidth $InnerWidth))
    if ($IncludeIteration) {
        $iterationValue = if ($cappedTotal -gt 0) {
            "$CurrentIteration of $cappedTotal"
        } else { '' }
        $lines.Add((Format-TrackerMetadataRow -Label 'Iteration' -Value $iterationValue))
    }

    if ($features.Count -eq 0) {
        $lines.Add('')
        $lines.Add("${muted}No active features.${reset}")
        return $lines
    }

    foreach ($featureRow in $featureRows) {
        $lines.Add('')
        $lines.Add(
            "${accent}$($featureRow.Heading)${reset} " +
            "${muted}($($featureRow.Directory.Name))${reset}"
        )
        if ($featureRow.Tickets.Count -eq 0) {
            $lines.Add("${muted}└─ no tickets${reset}")
            continue
        }

        if (@($featureRow.Tickets | Where-Object { -not $_.Completed }).Count -eq 0) {
            $issueLabel = if ($featureRow.Tickets.Count -eq 1) { 'issue' } else { 'issues' }
            $lines.Add(
                "${muted}└─ [✓] All $($featureRow.Tickets.Count) $issueLabel completed${reset}"
            )
            continue
        }

        for ($index = 0; $index -lt $featureRow.Tickets.Count; $index++) {
            $ticket   = $featureRow.Tickets[$index]
            $branch   = if ($index -eq $featureRow.Tickets.Count - 1) { '└─' } else { '├─' }
            $ticketId = $ticket.File.BaseName
            $heading = Get-MarkdownHeading `
                -Path $ticket.File.FullName `
                -Fallback $ticketId
            if ($ticket.Completed) {
                $lines.Add("${muted}$branch [✓] $heading${reset}")
            }
            else {
                $lines.Add("$branch ${success}[ ]${reset} $heading")
            }
        }
    }

    return $lines
}

function Format-PanelTopBorder {
    param(
        [Parameter(Mandatory)]
        [string]
        $Label,

        [Parameter(Mandatory)]
        [int]
        $Width
    )

    if ($Width -lt 2) { $Width = 2 }

    # Intensity alone inherits the current foreground colour. Select grey
    # explicitly so a coloured label cannot bleed into either frame border.
    $frame  = "`e[2;38;5;8m"
    $accent = $PSStyle.Foreground.BrightCyan
    $reset  = $PSStyle.Reset

    # Top border: ╭─ <label> ─...─╮  (total printable width = $Width)
    # Structure: ╭─(2) + space(1) + label + space(1) + fill + ╮(1)
    $fillLen = [Math]::Max(0, $Width - 4 - $Label.Length - 1)
    return "${frame}╭─ ${accent}${Label}${frame} $('─' * $fillLen)╮${reset}"
}

function Format-PanelBottomBorder {
    param(
        [Parameter(Mandatory)]
        [int]
        $Width
    )

    if ($Width -lt 2) { $Width = 2 }

    $frame = "`e[2;38;5;8m"
    $reset = $PSStyle.Reset
    return "${frame}╰$('─' * ($Width - 2))╯${reset}"
}

function Get-AgentOutputBlankRow {
    param(
        [Parameter(Mandatory)]
        [int]
        $InnerWidth
    )

    $frame = "`e[2;38;5;8m"
    $reset = $PSStyle.Reset
    return "${frame}│${reset}$(' ' * ($InnerWidth + 2))${frame}│${reset}"
}

function Get-DisplayCellWidth {
    param(
        [Parameter()]
        [AllowNull()]
        [string]
        $Text
    )

    if ($null -eq $Text -or $Text.Length -eq 0) { return 0 }

    $width = 0
    $index = 0
    while ($index -lt $Text.Length) {
        $controlLength = Get-TerminalControlSequenceLength -Text $Text -StartIndex $index
        if ($controlLength -gt 0) {
            $index += $controlLength
            continue
        }

        $codePoint = [char]::ConvertToUtf32($Text, $index)
        $charLen = if ($codePoint -gt 0xFFFF) { 2 } else { 1 }
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($Text, $index)
        $cellWidth = switch ($category) {
            ([System.Globalization.UnicodeCategory]::Control) { 0; break }
            ([System.Globalization.UnicodeCategory]::NonSpacingMark) { 0; break }
            ([System.Globalization.UnicodeCategory]::SpacingCombiningMark) { 0; break }
            ([System.Globalization.UnicodeCategory]::EnclosingMark) { 0; break }
            default {
                if (
                    $codePoint -eq 0x200D -or
                    ($codePoint -ge 0xFE00 -and $codePoint -le 0xFE0F)
                ) {
                    0
                }
                elseif (
                    ($codePoint -ge 0x1100 -and $codePoint -le 0x115F) -or
                    ($codePoint -ge 0x2329 -and $codePoint -le 0x232A) -or
                    ($codePoint -ge 0x2E80 -and $codePoint -le 0xA4CF) -or
                    ($codePoint -ge 0xAC00 -and $codePoint -le 0xD7A3) -or
                    ($codePoint -ge 0xF900 -and $codePoint -le 0xFAFF) -or
                    ($codePoint -ge 0xFE10 -and $codePoint -le 0xFE19) -or
                    ($codePoint -ge 0xFE30 -and $codePoint -le 0xFE6F) -or
                    ($codePoint -ge 0xFF00 -and $codePoint -le 0xFF60) -or
                    ($codePoint -ge 0xFFE0 -and $codePoint -le 0xFFE6) -or
                    ($codePoint -ge 0x1F300 -and $codePoint -le 0x1FAFF) -or
                    ($codePoint -ge 0x20000 -and $codePoint -le 0x3FFFD)
                ) {
                    2
                }
                else {
                    1
                }
            }
        }

        $width += $cellWidth
        $index += $charLen
    }

    return $width
}

function Get-TerminalControlSequenceLength {
    param(
        [Parameter(Mandatory)]
        [string]
        $Text,

        [Parameter(Mandatory)]
        [int]
        $StartIndex
    )

    if ($StartIndex + 1 -ge $Text.Length -or $Text[$StartIndex] -ne [char]27) {
        return 0
    }

    if ($Text[$StartIndex + 1] -eq '[') {
        for ($index = $StartIndex + 2; $index -lt $Text.Length; $index++) {
            $value = [int][char]$Text[$index]
            if ($value -ge 0x40 -and $value -le 0x7E) {
                return $index - $StartIndex + 1
            }
        }
        return 0
    }

    if ($Text[$StartIndex + 1] -eq ']') {
        for ($index = $StartIndex + 2; $index -lt $Text.Length; $index++) {
            if ($Text[$index] -eq [char]7) { return $index - $StartIndex + 1 }
            if ($Text[$index] -eq [char]27 -and
                ($index + 1) -lt $Text.Length -and $Text[$index + 1] -eq '\') {
                return $index - $StartIndex + 2
            }
        }
    }

    return 0
}

function Add-AgentOutputWrappedLine {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IList]
        $Rows,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '',

        [Parameter(Mandatory)]
        [int]
        $InnerWidth,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $ContinuationPrefix = '',

        [Parameter()]
        [switch]
        $HardWrap
    )

    $tokens = [System.Collections.Generic.List[pscustomobject]]::new()
    $activeStyle = ''
    $activeHyperlink = ''
    $osc8Prefix = "$([char]27)]8;;"
    $osc8Close = "$osc8Prefix$([char]27)\"
    $rowWidth = 0
    $lastWhitespace = -1
    $index = 0
    while ($index -lt $Content.Length) {
        $controlLength = Get-TerminalControlSequenceLength -Text $Content -StartIndex $index
        if ($controlLength -gt 0) {
            $sequence = $Content.Substring($index, $controlLength)
            $tokens.Add([pscustomobject]@{
                    Text         = $sequence
                    Width        = 0
                    IsWhitespace = $false
                })
            if ($sequence.EndsWith('m', [System.StringComparison]::Ordinal)) {
                if ($sequence -match "`e\[(?:0;?)*m") {
                    $activeStyle = ''
                }
                if ($sequence -notmatch "`e\[0m") {
                    $activeStyle += $sequence
                }
            }
            if ($sequence.StartsWith($osc8Prefix, [System.StringComparison]::Ordinal)) {
                $activeHyperlink = if ($sequence -ceq $osc8Close) { '' } else { $sequence }
            }
            $index += $controlLength
            continue
        }

        $codePoint = [char]::ConvertToUtf32($Content, $index)
        $charLen = if ($codePoint -gt 0xFFFF) { 2 } else { 1 }
        $textElement = $Content.Substring($index, $charLen)
        $elementWidth = Get-DisplayCellWidth -Text $textElement
        if (
            $InnerWidth -gt 0 -and
            $elementWidth -gt 0 -and
            $rowWidth -gt 0 -and
            ($rowWidth + $elementWidth -gt $InnerWidth)
        ) {
            if (-not $HardWrap -and $lastWhitespace -ge 0) {
                $rowTokens = @($tokens.GetRange(0, $lastWhitespace))
                $remainingTokens = @(
                    $tokens.GetRange($lastWhitespace + 1, $tokens.Count - $lastWhitespace - 1)
                )
                $rowText = ($rowTokens | ForEach-Object Text) -join ''
                if (-not [string]::IsNullOrEmpty($activeHyperlink)) {
                    $rowText += $osc8Close
                }
                $rowDisplayWidth = ($rowTokens | Measure-Object -Property Width -Sum).Sum
                $Rows.Add([pscustomobject]@{
                        Text  = $rowText
                        Width = [int]$rowDisplayWidth
                    })

                $tokens = [System.Collections.Generic.List[pscustomobject]]::new()
                $rowWidth = 0
                $lastWhitespace = -1
                if (-not [string]::IsNullOrEmpty($activeStyle)) {
                    $tokens.Add([pscustomobject]@{
                            Text         = $activeStyle
                            Width        = 0
                            IsWhitespace = $false
                        })
                }
                if (-not [string]::IsNullOrEmpty($activeHyperlink)) {
                    $tokens.Add([pscustomobject]@{
                            Text         = $activeHyperlink
                            Width        = 0
                            IsWhitespace = $false
                        })
                }
                if (-not [string]::IsNullOrEmpty($ContinuationPrefix)) {
                    $tokens.Add([pscustomobject]@{
                            Text         = $ContinuationPrefix
                            Width        = Get-DisplayCellWidth -Text $ContinuationPrefix
                            IsWhitespace = $false
                        })
                    $rowWidth = Get-DisplayCellWidth -Text $ContinuationPrefix
                }
                foreach ($remainingToken in $remainingTokens) {
                    if ($rowWidth -eq 0 -and $remainingToken.IsWhitespace) { continue }
                    $tokens.Add($remainingToken)
                    $rowWidth += [int]$remainingToken.Width
                    if ($remainingToken.IsWhitespace) {
                        $lastWhitespace = $tokens.Count - 1
                    }
                }
            }
            else {
                $rowText = ($tokens | ForEach-Object Text) -join ''
                if (-not [string]::IsNullOrEmpty($activeHyperlink)) {
                    $rowText += $osc8Close
                }
                $Rows.Add([pscustomobject]@{
                        Text  = $rowText
                        Width = $rowWidth
                    })
                $tokens.Clear()
                if (-not [string]::IsNullOrEmpty($activeStyle)) {
                    $tokens.Add([pscustomobject]@{
                            Text         = $activeStyle
                            Width        = 0
                            IsWhitespace = $false
                        })
                }
                if (-not [string]::IsNullOrEmpty($activeHyperlink)) {
                    $tokens.Add([pscustomobject]@{
                            Text         = $activeHyperlink
                            Width        = 0
                            IsWhitespace = $false
                        })
                }
                if (-not [string]::IsNullOrEmpty($ContinuationPrefix)) {
                    $tokens.Add([pscustomobject]@{
                            Text         = $ContinuationPrefix
                            Width        = Get-DisplayCellWidth -Text $ContinuationPrefix
                            IsWhitespace = $false
                        })
                    $rowWidth = Get-DisplayCellWidth -Text $ContinuationPrefix
                }
                else {
                    $rowWidth = 0
                }
                $lastWhitespace = -1
            }
        }

        $tokens.Add([pscustomobject]@{
                Text         = $textElement
                Width        = $elementWidth
                IsWhitespace = [char]::IsWhiteSpace($Content, $index)
            })
        $rowWidth += $elementWidth
        if ([char]::IsWhiteSpace($Content, $index)) {
            $lastWhitespace = $tokens.Count - 1
        }
        $index += $charLen
    }

    $rowText = ($tokens | ForEach-Object Text) -join ''
    if (-not [string]::IsNullOrEmpty($activeHyperlink)) {
        $rowText += $osc8Close
    }
    $Rows.Add([pscustomobject]@{
            Text  = $rowText
            Width = $rowWidth
        })
}

function Split-AgentOutputContent {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '',

        [Parameter(Mandatory)]
        [int]
        $InnerWidth
    )

    if ($InnerWidth -lt 0) { $InnerWidth = 0 }
    if ($null -eq $Content) { $Content = '' }

    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    $index = 0
    $lineStart = 0
    while ($index -lt $Content.Length) {
        if ($Content[$index] -eq "`n" -or $Content[$index] -eq "`r") {
            $line = $Content.Substring($lineStart, $index - $lineStart)
            $isCodeRow = $line.StartsWith([string][char]0x1E, [System.StringComparison]::Ordinal)
            if ($isCodeRow) { $line = $line.Substring(1) }
            $plainLine = $line -replace "`e\[[0-?]*[ -/]*[@-~]", ''
            $continuationPrefix = ''
            if ($isCodeRow) {
                $continuationPrefix = '↪ '
            }
            elseif ($plainLine -match '^((?:│ )*)(\s*)(?:• |\[[ ✓]\] |\d+[.)] )') {
                $continuationPrefix = $matches[1] + $matches[2] + (' ' * (
                        Get-DisplayCellWidth -Text $matches[3]
                    ))
            }
            elseif ($plainLine -match '^((?:│ )+)') {
                $continuationPrefix = $matches[1]
            }
            Add-AgentOutputWrappedLine `
                -Rows $rows `
                -Content $line `
                -InnerWidth $InnerWidth `
                -ContinuationPrefix $continuationPrefix `
                -HardWrap:$isCodeRow
            if (
                $Content[$index] -eq "`r" -and
                ($index + 1) -lt $Content.Length -and
                $Content[$index + 1] -eq "`n"
            ) {
                $index++
            }
            $index++
            $lineStart = $index
            continue
        }
        $index++
    }

    $line = $Content.Substring($lineStart)
    $isCodeRow = $line.StartsWith([string][char]0x1E, [System.StringComparison]::Ordinal)
    if ($isCodeRow) { $line = $line.Substring(1) }
    $plainLine = $line -replace "`e\[[0-?]*[ -/]*[@-~]", ''
    $continuationPrefix = ''
    if ($isCodeRow) {
        $continuationPrefix = '↪ '
    }
    elseif ($plainLine -match '^((?:│ )*)(\s*)(?:• |\[[ ✓]\] |\d+[.)] )') {
        $continuationPrefix = $matches[1] + $matches[2] + (' ' * (
                Get-DisplayCellWidth -Text $matches[3]
            ))
    }
    elseif ($plainLine -match '^((?:│ )+)') {
        $continuationPrefix = $matches[1]
    }
    Add-AgentOutputWrappedLine `
        -Rows $rows `
        -Content $line `
        -InnerWidth $InnerWidth `
        -ContinuationPrefix $continuationPrefix `
        -HardWrap:$isCodeRow

    return @($rows)
}

function Write-AgentOutputRow {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '',

        [Parameter(Mandatory)]
        [int]
        $InnerWidth,

        [Parameter()]
        [hashtable]
        $WorkboardState
    )

    $frame = "`e[2;38;5;8m"
    $reset = $PSStyle.Reset
    $rows = Split-AgentOutputContent -Content $Content -InnerWidth $InnerWidth
    foreach ($row in $rows) {
        $pad = ' ' * [Math]::Max(0, $InnerWidth - [int]$row.Width)
        [Console]::Write("${frame}│${reset} $($row.Text)$pad ${frame}│${reset}")
        Invoke-RalphFramedRowAdvance -WorkboardState $WorkboardState
    }
}

function Invoke-RalphFramedRowAdvance {
    param(
        [Parameter()]
        [hashtable]
        $WorkboardState
    )

    # CR clears delayed autowrap before LF advances inside the message margin.
    [Console]::Write("`r`n")
    if ($null -eq $WorkboardState) {
        return
    }

    $messageBottom = [int]$WorkboardState.MessageBottom
    $cursorRow = [int]$WorkboardState.MessageCursorRow
    if ($cursorRow -lt $messageBottom) {
        $WorkboardState.MessageCursorRow = $cursorRow + 1
        return
    }

    # Scrolling creates an unframed blank bottom row. Repaint it and leave the
    # cursor at its start so the next message replaces that row normally.
    $blankRow = Get-AgentOutputBlankRow -InnerWidth ([int]$WorkboardState.InnerWidth)
    [Console]::Write("`e[${messageBottom};1H$blankRow`e[${messageBottom};1H")
}

function Get-TypedAgentOutputPlan {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '',

        [Parameter(Mandatory)]
        [int]
        $ContentWidth,

        [Parameter(Mandatory)]
        [int]
        $InnerWidth
    )

    $frame = "`e[2;38;5;8m"
    $reset = $PSStyle.Reset
    $pad = ' ' * [Math]::Max(0, $InnerWidth - $ContentWidth)
    $operations = [System.Collections.Generic.List[object]]::new()
    $operations.Add([pscustomobject]@{ Kind = 'Write'; Text = "${frame}│${reset} " })

    $index = 0
    $cellsSincePause = 0
    while ($index -lt $Content.Length) {
        $controlLength = Get-TerminalControlSequenceLength -Text $Content -StartIndex $index
        if ($controlLength -gt 0) {
            $operations.Add([pscustomobject]@{
                    Kind = 'Write'; Text = $Content.Substring($index, $controlLength)
                })
            $index += $controlLength
            continue
        }

        $codePoint = [char]::ConvertToUtf32($Content, $index)
        $elementLength = if ($codePoint -gt 0xFFFF) { 2 } else { 1 }
        $element = $Content.Substring($index, $elementLength)
        $operations.Add([pscustomobject]@{ Kind = 'Write'; Text = $element })
        $elementWidth = Get-DisplayCellWidth -Text $element
        if ($elementWidth -gt 0) {
            $cellsSincePause += $elementWidth
            if ($cellsSincePause -ge 2) {
                $operations.Add([pscustomobject]@{ Kind = 'Pause'; Duration = 8 })
                $cellsSincePause %= 2
            }
        }
        $index += $elementLength
    }

    $operations.Add([pscustomobject]@{ Kind = 'WriteLine'; Text = "$pad ${frame}│${reset}" })
    return @($operations)
}

function Invoke-TerminalOutputPlan {
    param(
        [Parameter(Mandatory)]
        [object[]]
        $Operations,

        [Parameter()]
        [hashtable]
        $WorkboardState
    )

    foreach ($operation in $Operations) {
        switch ($operation.Kind) {
            'Write' { [Console]::Write([string]$operation.Text); break }
            'WriteLine' {
                [Console]::Write([string]$operation.Text)
                Invoke-RalphFramedRowAdvance -WorkboardState $WorkboardState
                break
            }
            'Pause' { Start-Sleep -Milliseconds ([int]$operation.Duration); break }
            default { throw "Unsupported terminal operation kind: $($operation.Kind)" }
        }
    }
}

function Write-TypedAgentOutputRow {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '',

        [Parameter(Mandatory)]
        [int]
        $ContentWidth,

        [Parameter(Mandatory)]
        [int]
        $InnerWidth,

        [Parameter()]
        [hashtable]
        $WorkboardState
    )

    $plan = Get-TypedAgentOutputPlan -Content $Content -ContentWidth $ContentWidth `
        -InnerWidth $InnerWidth
    Invoke-TerminalOutputPlan -Operations $plan -WorkboardState $WorkboardState
}

function Compact-AgentOutputPanel {
    param(
        [Parameter(Mandatory)]
        [hashtable]
        $State
    )

    $oldBottomRow = if ($State.ContainsKey('BottomRow')) { [int]$State.BottomRow } else { 0 }
    if ($oldBottomRow -le 0) { return }

    $windowWidth = try { [Console]::WindowWidth } catch { 0 }
    if ($windowWidth -lt 1) {
        $windowWidth = [Math]::Max(2, (4 + [int]$State.InnerWidth))
    }
    $windowHeight = try { [Console]::WindowHeight } catch { 0 }
    if ($windowHeight -lt 1) {
        $windowHeight = if ($State.ContainsKey('WindowHeight')) {
            [int]$State.WindowHeight
        }
        else {
            $oldBottomRow
        }
    }

    $newBottomRow = try { [Console]::CursorTop + 1 } catch { 0 }
    $messageTop = if ($State.ContainsKey('ScrollTop')) { [int]$State.ScrollTop } else { 1 }
    if ($newBottomRow -lt $messageTop -or $newBottomRow -gt $oldBottomRow) {
        $newBottomRow = if ($State.ContainsKey('MessageCursorRow')) {
            [int]$State.MessageCursorRow
        }
        else {
            $oldBottomRow
        }
    }
    $newBottomRow = [Math]::Min($oldBottomRow, [Math]::Max($messageTop, $newBottomRow))
    $newBottomRow = [Math]::Min($windowHeight, $newBottomRow)

    if ($oldBottomRow -gt $newBottomRow) {
        $blankLine = ' ' * $windowWidth
        for ($row = $newBottomRow; $row -le $oldBottomRow; $row++) {
            [Console]::Write("`e[${row};1H$blankLine")
        }
    }

    [Console]::Write("`e[${newBottomRow};1H")
    [Console]::Write((Format-PanelBottomBorder -Width $windowWidth))
    $State.BottomRow = $newBottomRow
    $State.MessageBottom = [Math]::Max($messageTop, $newBottomRow - 1)
    $State.MessageCursorRow = $State.MessageBottom
}

function Get-AgentOutputPanelLayout {
    param(
        [Parameter(Mandatory)]
        [int]
        $TrackerPanelHeight,

        [Parameter(Mandatory)]
        [int]
        $WindowWidth,

        [Parameter(Mandatory)]
        [int]
        $WindowHeight
    )

    if ($WindowWidth -lt 1) { $WindowWidth = 120 }
    if ($WindowHeight -lt 1) { $WindowHeight = 24 }

    $messageTop = [Math]::Min(
        [Math]::Max(1, $TrackerPanelHeight + 2),
        $WindowHeight
    )
    $messageBottom = [Math]::Max($messageTop, $WindowHeight - 1)
    $topRow = [Math]::Max(1, $messageTop - 1)
    $bottomRow = [Math]::Min($WindowHeight, $messageBottom + 1)

    return @{
        TopRow      = $topRow
        BottomRow   = $bottomRow
        MessageTop  = $messageTop
        MessageBottom = $messageBottom
        InnerWidth  = [Math]::Max(0, $WindowWidth - 4)
        TopBorder   = Format-PanelTopBorder -Label 'Agent output' -Width $WindowWidth
        BottomBorder = Format-PanelBottomBorder -Width $WindowWidth
    }
}

function Get-RalphWorkboardDimensions {
    if (-not [string]::IsNullOrWhiteSpace($env:RALPH_TEST_WORKBOARD_DIMENSIONS)) {
        if (-not (Get-Variable -Name RalphTestDimensionQueue -Scope Script -ErrorAction SilentlyContinue)) {
            $script:RalphTestDimensionQueue = [System.Collections.Generic.Queue[object]]::new()
            foreach ($item in $env:RALPH_TEST_WORKBOARD_DIMENSIONS -split ';') {
                if ($item -notmatch '^(?<Width>\d+)x(?<Height>\d+)$') {
                    throw "Invalid RALPH_TEST_WORKBOARD_DIMENSIONS item: $item"
                }
                $script:RalphTestDimensionQueue.Enqueue(@{
                        Width = [int]$Matches.Width
                        Height = [int]$Matches.Height
                    })
            }
        }
        if ($script:RalphTestDimensionQueue.Count -gt 0) {
            return $script:RalphTestDimensionQueue.Dequeue()
        }
    }

    $width = try { [Console]::WindowWidth } catch { 0 }
    if ($width -lt 1) { $width = 120 }
    $height = try { [Console]::WindowHeight } catch { 0 }
    if ($height -lt 1) { $height = 24 }
    return @{ Width = $width; Height = $height }
}

function Refresh-RalphWorkboardForResize {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [hashtable]
        $State
    )

    $dimensions = Get-RalphWorkboardDimensions
    if (
        [int]$dimensions.Width -eq [int]$State.WindowWidth -and
        [int]$dimensions.Height -eq [int]$State.WindowHeight
    ) {
        return $State
    }

    return Update-RalphWorkboard -ScratchDirectory $ScratchDirectory -State $State `
        -WindowWidth ([int]$dimensions.Width) -WindowHeight ([int]$dimensions.Height) `
        -ForceFullRedraw
}

function Format-TrackerPanel {
    param(
        [string[]]
        $TrackerLines,

        [Parameter(Mandatory)]
        [int]
        $Width
    )

    if ($Width -lt 2) { $Width = 2 }
    $frame       = "`e[2;38;5;8m"
    $reset       = $PSStyle.Reset
    $topBorder   = Format-PanelTopBorder -Label 'Ralph tracker' -Width $Width
    $bottomBorder = Format-PanelBottomBorder -Width $Width

    # Inner content area width: Width - │(1) - space(1) - space(1) - │(1) = Width - 4
    $innerWidth = [Math]::Max(0, $Width - 4)

    $result = [System.Collections.Generic.List[string]]::new()
    $result.Add($topBorder)
    foreach ($line in $TrackerLines) {
        # Strip ANSI sequences to calculate visible length for right-padding.
        $visible  = $line -replace "`e\[[^m]*m", ''
        $padCount = [Math]::Max(0, $innerWidth - $visible.Length)
        $result.Add("${frame}│${reset} ${line}$(' ' * $padCount) ${frame}│${reset}")
    }
    $result.Add($bottomBorder)

    return $result
}

function Show-RalphTracker {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [string]
        $Repository
    )

    foreach ($line in Get-TrackerLines -ScratchDirectory $ScratchDirectory `
        -Repository $Repository -IncludeIteration:$false) {
        Write-Host $line
    }
}

function Enter-RalphWorkboard {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [string]
        $Repository,

        [Parameter(Mandatory)]
        [string]
        $AgentSummary,

        [Parameter(Mandatory)]
        [int]
        $CurrentIteration,

        [Parameter(Mandatory)]
        [int]
        $TotalIterations,

        [Parameter()]
        [string[]]
        $DisplayFeatureNames = @()
    )

    $displayFeatureNameSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($displayFeatureName in $DisplayFeatureNames) {
        if (-not [string]::IsNullOrWhiteSpace($displayFeatureName)) {
            [void] $displayFeatureNameSet.Add($displayFeatureName)
        }
    }
    $normalizedDisplayFeatureNames = @($displayFeatureNameSet)

    # Snapshot active features at startup so they can be retained after archival.
    $startupFeatureNames = @(
        Get-ActiveTrackerFeatures -ScratchDirectory $ScratchDirectory |
            Where-Object {
                $displayFeatureNameSet.Count -eq 0 -or
                $displayFeatureNameSet.Contains($_.Name)
            } |
            ForEach-Object { $_.Name }
    )

    $windowWidth   = try { [Console]::WindowWidth } catch { 0 }
    if ($windowWidth -lt 1) { $windowWidth = 120 }
    $lines         = Get-TrackerLines `
        -ScratchDirectory $ScratchDirectory `
        -DisplayFeatureNames $normalizedDisplayFeatureNames `
        -Repository $Repository `
        -AgentSummary $AgentSummary `
        -InnerWidth ([Math]::Max(0, $windowWidth - 4)) `
        -CurrentIteration $CurrentIteration `
        -TotalIterations $TotalIterations
    $trackerHeight = $lines.Count
    $windowHeight  = try { [Console]::WindowHeight } catch { 0 }
    if ($windowHeight -lt 1) { $windowHeight = 24 }

    $panelLines   = Format-TrackerPanel -TrackerLines $lines -Width $windowWidth
    $panelHeight  = $panelLines.Count  # trackerHeight + 2 borders
    $outputLayout = Get-AgentOutputPanelLayout `
        -TrackerPanelHeight $panelHeight `
        -WindowWidth $windowWidth `
        -WindowHeight $windowHeight

    # Hide the cursor for the duration of the interactive workboard.
    [Console]::Write("`e[?25l")
    # Clear the screen and draw the tracker panel at the top.
    [Console]::Write("`e[2J`e[1;1H")
    foreach ($panelLine in $panelLines) {
        [Console]::WriteLine($panelLine)
    }
    [Console]::Write("`e[$($outputLayout.TopRow);1H")
    [Console]::WriteLine($outputLayout.TopBorder)
    # Draw blank rows explicitly before establishing the scroll region. Without
    # these rows, vertical frame edges appear only after the agent emits output.
    $blankOutputRow = Get-AgentOutputBlankRow -InnerWidth $outputLayout.InnerWidth
    for ($row = $outputLayout.MessageTop; $row -le $outputLayout.MessageBottom; $row++) {
        [Console]::Write("`e[${row};1H$blankOutputRow")
    }
    [Console]::Write("`e[$($outputLayout.BottomRow);1H")
    [Console]::Write($outputLayout.BottomBorder)

    # Confine scrolling to the agent-output region between fixed borders.
    [Console]::Write(
        "`e[$($outputLayout.MessageTop);$($outputLayout.MessageBottom)r"
    )
    [Console]::Write("`e[$($outputLayout.MessageTop);1H")

    return @{
        Height               = $trackerHeight
        ScrollTop            = $outputLayout.MessageTop
        MessageBottom         = $outputLayout.MessageBottom
        MessageCursorRow      = $outputLayout.MessageTop
        BottomRow            = $outputLayout.BottomRow
        InnerWidth           = $outputLayout.InnerWidth
        WindowWidth          = $windowWidth
        WindowHeight         = $windowHeight
        RetainedFeatureNames = $startupFeatureNames
        DisplayFeatureNames  = $normalizedDisplayFeatureNames
        Repository           = $Repository
        AgentSummary         = $AgentSummary
        CurrentIteration     = $CurrentIteration
        TotalIterations      = $TotalIterations
        CompletedIterations  = 0
    }
}

function Update-RalphWorkboard {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [hashtable]
        $State,

        [Parameter()]
        [int]
        $WindowWidth = 0,

        [Parameter()]
        [int]
        $WindowHeight = 0,

        [Parameter()]
        [switch]
        $ForceFullRedraw
    )

    $retainedNames = if ($State.ContainsKey('RetainedFeatureNames')) {
        $State.RetainedFeatureNames
    }
    else {
        @()
    }
    $displayNames = if ($State.ContainsKey('DisplayFeatureNames')) {
        $State.DisplayFeatureNames
    }
    else {
        @()
    }
    $repository = if ($State.ContainsKey('Repository')) {
        [string] $State.Repository
    }
    else {
        ''
    }
    $agentSummary = if ($State.ContainsKey('AgentSummary')) {
        [string] $State.AgentSummary
    }
    else {
        ''
    }
    $currentIteration = if ($State.ContainsKey('CurrentIteration')) {
        [int] $State.CurrentIteration
    }
    else {
        0
    }
    $totalIterations = if ($State.ContainsKey('TotalIterations')) {
        [int] $State.TotalIterations
    }
    else {
        0
    }
    $completedIterations = if ($State.ContainsKey('CompletedIterations')) {
        [int] $State.CompletedIterations
    }
    else {
        0
    }
    $lineWidth = $WindowWidth
    if ($lineWidth -lt 1) { $lineWidth = try { [Console]::WindowWidth } catch { 0 } }
    if ($lineWidth -lt 1) { $lineWidth = 120 }
    $lines = Get-TrackerLines -ScratchDirectory $ScratchDirectory `
        -RetainedFeatureNames $retainedNames `
        -DisplayFeatureNames $displayNames `
        -Repository $repository `
        -AgentSummary $agentSummary `
        -InnerWidth ([Math]::Max(0, $lineWidth - 4)) `
        -CurrentIteration $currentIteration `
        -TotalIterations $totalIterations `
        -CompletedIterations $completedIterations
    $trackerHeight = $lines.Count
    $currentHeight = if ($State.ContainsKey('Height')) { [int]$State.Height } else { 0 }

    if ($ForceFullRedraw) {
        # Keep the last valid workboard intact while the terminal cannot fit the
        # prospective tracker panel, both Agent output borders, and one scrollable
        # message row. Leaving the rendered dimensions unchanged makes a later
        # output row retry the resize and recover automatically.
        $minimumWindowHeight = $trackerHeight + 5
        if ($lineWidth -lt 5 -or $WindowHeight -lt $minimumWindowHeight) {
            return $State
        }
    }

    $panelLines  = Format-TrackerPanel -TrackerLines $lines -Width $lineWidth
    $panelHeight = $panelLines.Count  # trackerHeight + 2 borders

    if ($ForceFullRedraw -or $trackerHeight -ne $currentHeight) {
        # Tracker-height changes must reposition both adjacent panels and recreate
        # the message scroll region so borders and content remain coherent.
        $windowHeight = $WindowHeight
        if ($windowHeight -lt 1) {
            $windowHeight = try { [Console]::WindowHeight } catch { 0 }
        }
        if ($windowHeight -lt 1) {
            if ($State.ContainsKey('WindowHeight')) {
                $windowHeight = [int]$State.WindowHeight
            }
            else {
                $windowHeight = 24
            }
        }
        $outputLayout = Get-AgentOutputPanelLayout `
            -TrackerPanelHeight $panelHeight `
            -WindowWidth $lineWidth `
            -WindowHeight $windowHeight

        [Console]::Write("`e[2J`e[1;1H")
        foreach ($panelLine in $panelLines) {
            [Console]::WriteLine($panelLine)
        }
        [Console]::Write("`e[$($outputLayout.TopRow);1H")
        [Console]::WriteLine($outputLayout.TopBorder)
        $blankOutputRow = Get-AgentOutputBlankRow -InnerWidth $outputLayout.InnerWidth
        for ($row = $outputLayout.MessageTop; $row -le $outputLayout.MessageBottom; $row++) {
            [Console]::Write("`e[${row};1H$blankOutputRow")
        }
        [Console]::Write("`e[$($outputLayout.BottomRow);1H")
        [Console]::Write($outputLayout.BottomBorder)
        [Console]::Write(
            "`e[$($outputLayout.MessageTop);$($outputLayout.MessageBottom)r"
        )
        [Console]::Write("`e[$($outputLayout.MessageTop);1H")

        $State.Height = $trackerHeight
        $State.ScrollTop = $outputLayout.MessageTop
        $State.MessageBottom = $outputLayout.MessageBottom
        $State.MessageCursorRow = $outputLayout.MessageTop
        $State.BottomRow = $outputLayout.BottomRow
        $State.InnerWidth = $outputLayout.InnerWidth
        $State.WindowWidth = $lineWidth
        $State.WindowHeight = $windowHeight
        return $State
    }

    # Save the current scroll-region cursor position, redraw the panel, then restore.
    [Console]::Write("`e[s`e[1;1H")
    $blankLine       = ' ' * $lineWidth
    $oldPanelHeight  = $currentHeight + 2
    $rowsToRedraw    = [Math]::Max($oldPanelHeight, $panelHeight)
    for ($index = 0; $index -lt $rowsToRedraw; $index++) {
        if ($index -lt $panelHeight) {
            [Console]::WriteLine($panelLines[$index])
        }
        else {
            [Console]::WriteLine($blankLine)
        }
    }
    [Console]::Write("`e[u")

    return $State
}

function Exit-RalphWorkboard {
    param(
        [Parameter(Mandatory)]
        [hashtable]
        $State
    )

    # Restore the terminal's full-screen scrolling region.
    [Console]::Write("`e[r")
    # Position cursor at the bottom border row so the prompt appears below the frame.
    $bottomRow = if ($State.ContainsKey('BottomRow')) { [int]$State.BottomRow } else { 0 }
    if ($bottomRow -gt 0) {
        [Console]::Write("`e[${bottomRow};1H")
        [Console]::WriteLine()
    }
    # Make the cursor visible again after tearing down the interactive workboard.
    [Console]::Write("`e[?25h")
}

function Invoke-RalphCleanup {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory
    )

    $doneDirectory = Join-Path $ScratchDirectory 'done'
    $archiveDirectories = @(
        if (Test-Path -LiteralPath $doneDirectory -PathType Container) {
            Get-ChildItem -LiteralPath $doneDirectory -Directory
        }
    )
    foreach ($archive in $archiveDirectories) {
        if ($archive.Name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw "Unsafe archived feature directory: '$($archive.Name)'."
        }
    }

    foreach ($archive in $archiveDirectories) {
        Remove-Item -LiteralPath $archive.FullName -Recurse -Force
    }

    if ($archiveDirectories.Count -eq 0) {
        Write-Host 'Cleanup complete: nothing to remove.'
    }
    else {
        $removed = @($archiveDirectories.Name) | Sort-Object
        Write-Host "Cleanup complete: removed $($removed -join ', ')."
    }
}

function Resolve-RalphInvocation {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [hashtable]
        $BoundParameters,

        [switch] $List,
        [switch] $Cleanup,
        [AllowEmptyString()][string] $Archive,

        [Parameter(Mandatory)]
        [ValidateSet('codex', 'copilot')]
        [string]
        $Agent,

        [AllowEmptyString()][string] $Model,
        [AllowEmptyString()][string] $Effort,
        [AllowEmptyString()][string] $Feature
    )

    foreach ($optionName in 'Model', 'Effort') {
        if ($BoundParameters.ContainsKey($optionName) -and
            [string]::IsNullOrWhiteSpace([string]$BoundParameters[$optionName])) {
            throw "-$optionName must be a non-empty value."
        }
    }

    $mode = 'Run'
    $incompatibleOptions = @()
    if ($BoundParameters.ContainsKey('Archive')) {
        $mode = 'Archive'
        $incompatibleOptions = @(
            @('List', 'Cleanup', 'Agent', 'Model', 'Effort', 'Iterations', 'Feature') |
                Where-Object { $BoundParameters.ContainsKey($_) }
        )
    }
    elseif ($List) {
        $mode = 'List'
        $incompatibleOptions = @(
            @('Cleanup', 'Archive', 'Agent', 'Model', 'Effort', 'Iterations', 'Feature') |
                Where-Object { $BoundParameters.ContainsKey($_) }
        )
    }
    elseif ($Cleanup) {
        $mode = 'Cleanup'
        $incompatibleOptions = @(
            @('Archive', 'Agent', 'Model', 'Effort', 'Iterations', 'Feature') |
                Where-Object { $BoundParameters.ContainsKey($_) }
        )
    }

    if ($incompatibleOptions.Count -gt 0) {
        throw "-$mode cannot be combined with: $($incompatibleOptions -join ', ')."
    }

    $identity = if ($mode -eq 'Archive') { $Archive } elseif (
        $BoundParameters.ContainsKey('Feature')
    ) { $Feature } else { $null }
    if ($null -ne $identity) {
        $candidate = Join-Path $ScratchDirectory $identity
        if ($identity -ceq 'done' -or
            [System.IO.Path]::GetFileName($identity) -cne $identity -or
            -not (Test-Path -LiteralPath $candidate -PathType Container) -or
            -not (Test-Path -LiteralPath (Join-Path $candidate 'spec.md') -PathType Leaf)) {
            $parameterName = if ($mode -eq 'Archive') { 'Archive' } else { 'Feature' }
            throw "$parameterName must name a direct active tracker folder containing spec.md: $identity"
        }
    }

    return [pscustomobject]@{
        Mode    = $mode
        Scope   = if ($BoundParameters.ContainsKey('Feature')) { 'feature' } else { 'automatic' }
        Feature = $Feature
        Archive = $Archive
        Agent   = [pscustomobject]@{
            Name   = $Agent
            Model  = if ($BoundParameters.ContainsKey('Model')) { $Model } else { 'gpt-5.6-luna' }
            Effort = if ($BoundParameters.ContainsKey('Effort')) { $Effort } else { 'medium' }
        }
    }
}

# Dot-sourcing is an intentionally private test seam. Keep all production setup
# and orchestration below this guard so importing the functions has no host,
# repository, terminal, or process side effects.
if ($MyInvocation.InvocationName -ne '.') {
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$git = Get-Command git -ErrorAction Stop

$repositoryRoot = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
    'rev-parse',
    '--show-toplevel'
)
$repositoryRoot = $repositoryRoot.Trim()

if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'Could not determine the Git repository root.'
}

Set-Location -LiteralPath $repositoryRoot

$scratchDirectory = Join-Path $repositoryRoot '.scratch'
if (-not (Test-Path -LiteralPath $scratchDirectory -PathType Container)) {
    throw "Local issue tracker directory not found: $scratchDirectory"
}

$invocation = Resolve-RalphInvocation `
    -ScratchDirectory $scratchDirectory `
    -BoundParameters $PSBoundParameters `
    -List:$List `
    -Cleanup:$Cleanup `
    -Archive $Archive `
    -Agent $Agent `
    -Model $Model `
    -Effort $Effort `
    -Feature $Feature

if ($invocation.Mode -eq 'Archive') {
    $archivePath = Move-CompletedTrackerFeature `
        -ScratchDirectory $scratchDirectory `
        -Feature $invocation.Archive `
        -AllowUnfinished
    $relativeArchivePath = [System.IO.Path]::GetRelativePath(
        $repositoryRoot,
        $archivePath
    )
    Write-Host "Archived feature '$($invocation.Archive)' to: $relativeArchivePath"
    exit 0
}

if ($invocation.Mode -eq 'List') {
    Show-RalphTracker -ScratchDirectory $scratchDirectory -Repository $repositoryRoot
    exit 0
}

$progressFile = Join-Path $scratchDirectory 'progress.jsonl'
if (-not (Test-Path -LiteralPath $progressFile -PathType Leaf)) {
    New-Item -ItemType File -Path $progressFile | Out-Null
}

if ($invocation.Mode -eq 'Cleanup') {
    Invoke-RalphCleanup -ScratchDirectory $scratchDirectory
    exit 0
}

$gitStatus = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
    'status',
    '--porcelain'
)
if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
    throw 'The Git working tree is not clean. Commit or stash all changes before running Invoke-Ralph.'
}

Repair-ProgressHistoryTerminator -Path $progressFile | Out-Null

$scopeKind = $invocation.Scope
$scopeFeature = $invocation.Feature
$reconciliationFeatures = if ($scopeKind -eq 'feature') {
    @(
        Get-Item -LiteralPath (Join-Path $scratchDirectory $scopeFeature) -ErrorAction Stop
    )
}
else {
    @(Get-TrackerFeatureDirectories -ScratchDirectory $scratchDirectory)
}
foreach ($featureDirectory in $reconciliationFeatures) {
    Invoke-TrackerDependencyReconciliation -FeatureDirectory $featureDirectory.FullName |
        Out-Null
}
foreach ($featureDirectory in $reconciliationFeatures) {
    if (@(Get-UnfinishedTrackerTickets -FeatureDirectory $featureDirectory.FullName).Count -eq 0) {
        Move-CompletedTrackerFeature `
            -ScratchDirectory $scratchDirectory `
            -Feature $featureDirectory.Name | Out-Null
    }
}
if ($scopeKind -eq 'feature' -and -not (Test-Path -LiteralPath (
        Join-Path $scratchDirectory $scopeFeature
    ) -PathType Container)) {
    Write-Host 'Requested scope complete.'
    exit 0
}
if ($scopeKind -eq 'automatic' -and @(
        Get-ActiveTrackerFeatures -ScratchDirectory $scratchDirectory
    ).Count -eq 0) {
    Write-Host 'Requested scope complete.'
    exit 0
}

$agentCommand = Get-Command $Agent -ErrorAction Stop
$scopeInstruction = if ($scopeKind -eq 'feature') {
    $specPath = [System.IO.Path]::GetRelativePath(
        $repositoryRoot,
        (Join-Path (Join-Path $scratchDirectory $scopeFeature) 'spec.md')
    )

    @"
Work only on the selected feature '$scopeFeature', whose specification is '$specPath'.
Complete successive unfinished tickets for that feature until it archives.
Ralph determines completion from the resulting tracker state.
"@
}
else {
    $issueDirectories = @(
        Get-ActiveTrackerFeatures -ScratchDirectory $scratchDirectory |
            ForEach-Object {
                [System.IO.Path]::GetRelativePath(
                    $repositoryRoot,
                    (Join-Path $_.FullName 'issues')
                )
            }
    )

    if ($issueDirectories.Count -eq 0) {
        Write-Host 'Requested scope complete.'
        exit 0
    }

    $issueDirectoryList = $issueDirectories -join [Environment]::NewLine
    @"
Choose the highest-priority unfinished feature from these local issue directories:
$issueDirectoryList

Use the specs, tickets, dependencies, and tracker filenames to decide priority.
If a feature was started in an earlier iteration, continue it until it is complete
before selecting another feature.
"@
}

$prompt = @"
You are implementing work in the Git repository at '$repositoryRoot'.

$scopeInstruction

For this iteration:
1. Read the relevant spec, every ticket for the selected feature, repository
   instructions, and .scratch/progress.jsonl.
2. Select exactly one unblocked ticket that is not already recorded as completed.
3. Implement only that ticket as an end-to-end, verifiable slice.
4. Determine and run the repository's relevant tests, type checks, linters, or
   build checks. Do not claim completion if a relevant check fails.
5. Append exactly one JSON object on one line to .scratch/progress.jsonl with
   non-empty string fields "feature", "ticket", "changes", and "checks".
6. Leave ticket status changes, staging, and committing to Ralph after success.

Do not work on more than one ticket in this iteration. Do not modify ticket or spec
files merely to track status. Do not modify ticket status, rename tickets, or stage,
commit, push, rewrite history, reset, clean, discard unrelated work, use destructive
Git commands, or change anything outside this repository.

If the entire requested scope was already complete at the start, do not invent work
or request an empty commit.
"@

$isInteractive = (
    -not [Console]::IsOutputRedirected -and
    $host.Name -ceq 'ConsoleHost'
)
if ($env:RALPH_FORCE_INTERACTIVE -eq '1') { $isInteractive = $true }

$model = $invocation.Agent.Model
$effort = $invocation.Agent.Effort
$agentSummary = "$Agent / $model$(if ($effort) { " ($effort)" } else { '' })"

$workboardState = $null
$compactOutputPanelOnExit = $false
if ($isInteractive) {
    $workboardParameters = @{
        ScratchDirectory = $scratchDirectory
        Repository       = $repositoryRoot
        AgentSummary      = $agentSummary
        CurrentIteration  = 1
        TotalIterations   = $Iterations
    }
    if ($scopeKind -eq 'feature') {
        $workboardParameters.DisplayFeatureNames = @($scopeFeature)
    }
    $workboardState = Enter-RalphWorkboard @workboardParameters
}

try {

if (-not $workboardState) {
    Write-Host "Repository: $repositoryRoot"
    Write-Host "Agent: $agentSummary"
}

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    if ($workboardState -and $workboardState.CurrentIteration -ne $iteration) {
        $workboardState.CurrentIteration = $iteration
        $workboardState = Update-RalphWorkboard `
            -ScratchDirectory $scratchDirectory `
            -State $workboardState
    }

    if ($workboardState) {
        $frameWidth = [int]$workboardState.InnerWidth
        Write-AgentOutputRow -Content '' -InnerWidth $frameWidth `
            -WorkboardState $workboardState
        Write-AgentOutputRow -Content "`e[2mIteration $iteration of $Iterations`e[0m" `
            -InnerWidth $frameWidth -WorkboardState $workboardState
        Write-AgentOutputRow `
            -Content "`e[2m$('─' * [Math]::Min(40, $frameWidth))`e[0m" `
            -InnerWidth $frameWidth -WorkboardState $workboardState
    }
    else {
        Write-Host ''
        Write-Host "Iteration $iteration of $Iterations"
        Write-Host ('-' * 40)
    }

    if ($scopeKind -eq 'automatic') {
        $currentIssueDirectories = @(
            Get-ActiveTrackerFeatures -ScratchDirectory $scratchDirectory |
                ForEach-Object {
                    [System.IO.Path]::GetRelativePath(
                        $repositoryRoot,
                        (Join-Path $_.FullName 'issues')
                    )
                }
        )
        if ($currentIssueDirectories.Count -eq 0) {
            if ($workboardState) {
                Write-AgentOutputRow -Content 'Requested scope complete.' `
                    -InnerWidth ([int]$workboardState.InnerWidth) `
                    -WorkboardState $workboardState
                $compactOutputPanelOnExit = $true
            }
            else {
                Write-Host 'Requested scope complete.'
            }
            exit 0
        }
        $currentScopeInstruction = @"
Choose the highest-priority unfinished feature from these local issue directories:
$($currentIssueDirectories -join [Environment]::NewLine)

Use the specs, tickets, dependencies, and tracker filenames to decide priority.
If a feature was started in an earlier iteration, continue it until it is complete
before selecting another feature.
"@
        $prompt = $prompt.Replace($scopeInstruction, $currentScopeInstruction)
        $scopeInstruction = $currentScopeInstruction
    }

    $progressBeforeIteration = [System.IO.File]::ReadAllText($progressFile)
    $frameWidth = if ($workboardState) { [int]$workboardState.InnerWidth } else { 0 }
    $agentParameters = @{
        Name            = $Agent
        CommandPath     = $agentCommand.Source
        Prompt          = $prompt
        Model           = $model
        FrameInnerWidth = $frameWidth
        WorkboardState  = $workboardState
        ScratchDirectory = $scratchDirectory
    }
    if (-not [string]::IsNullOrEmpty($effort)) {
        $agentParameters.Effort = $effort
    }
    Invoke-Agent @agentParameters | Out-Null
    $progressAfterIteration = [System.IO.File]::ReadAllText($progressFile)
    $progressChanged = -not [string]::Equals(
        $progressBeforeIteration,
        $progressAfterIteration,
        [System.StringComparison]::Ordinal
    )
    $gitStatus = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'status',
        '--porcelain',
        '--untracked-files=all'
    )
    $hasChanges = $progressChanged -or -not [string]::IsNullOrWhiteSpace($gitStatus)

    if (-not $hasChanges) {
        throw 'The agent completed successfully but produced no changes.'
    }

    if (-not $progressChanged) {
        throw 'The agent changed the repository without updating .scratch/progress.jsonl.'
    }

    $progressEntry = Get-NewProgressEntry `
        -Before $progressBeforeIteration `
        -After $progressAfterIteration
    Assert-ProgressEntryMatchesScope -ProgressEntry $progressEntry `
        -ScopeFeature $scopeFeature -ScopeKind $scopeKind | Out-Null
    $completedTicket = Complete-TrackerTicket `
        -ScratchDirectory $scratchDirectory `
        -ProgressEntry $progressEntry
    Repair-ProgressHistoryTerminator -Path $progressFile | Out-Null
    $completedFeatureDirectory = Join-Path $scratchDirectory $progressEntry.feature
    Invoke-TrackerDependencyReconciliation `
        -FeatureDirectory $completedFeatureDirectory | Out-Null
    $archivePath = Move-CompletedTrackerFeature `
        -ScratchDirectory $scratchDirectory `
        -Feature $progressEntry.feature
    $featureCompleted = $null -ne $archivePath
    $commitSubject = "ralph: $($progressEntry.feature)/$completedTicket"
    if ($featureCompleted) {
        $commitSubject += ', FEATURE completed'
    }

    Invoke-NativeText -FilePath $git.Source -ArgumentList @('add', '--all') | Out-Null
    Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'add',
        '--force',
        '--',
        $progressFile
    ) | Out-Null
    Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'commit',
        '--message',
        $commitSubject
    ) | Out-Null
    if ($workboardState) {
        $workboardState.CurrentIteration = $iteration
        $workboardState.CompletedIterations = [int]$workboardState.CompletedIterations + 1
        $workboardState = Update-RalphWorkboard `
            -ScratchDirectory $scratchDirectory `
            -State $workboardState
    }

    $scopeComplete = switch ($scopeKind) {
        'feature' { $featureCompleted }
        'automatic' {
            @(
                Get-ActiveTrackerFeatures -ScratchDirectory $scratchDirectory
            ).Count -eq 0
        }
    }
    if ($scopeComplete) {
        if ($workboardState) {
            Write-AgentOutputRow -Content 'Requested scope complete.' `
                -InnerWidth ([int]$workboardState.InnerWidth) `
                -WorkboardState $workboardState
            $compactOutputPanelOnExit = $true
        }
        else {
            Write-Host 'Requested scope complete.'
        }
        exit 0
    }
}

if ($workboardState) {
    Write-AgentOutputRow -Content "Reached the iteration limit ($Iterations)." `
        -InnerWidth ([int]$workboardState.InnerWidth) `
        -WorkboardState $workboardState
}
else {
    Write-Host "Reached the iteration limit ($Iterations)."
}
exit 0

} finally {
    if ($workboardState) {
        if ($compactOutputPanelOnExit) {
            Compact-AgentOutputPanel -State $workboardState
        }
        Exit-RalphWorkboard -State $workboardState
    }
}
}

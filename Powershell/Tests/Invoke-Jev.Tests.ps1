#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Invoke-Jev' {
    BeforeAll {
        $script:jevPath = Join-Path $PSScriptRoot '../Startup/Invoke-Jev.ps1'
        $script:originalKey = $env:TYPESAFE_API_KEY
    }

    BeforeEach {
        $env:TYPESAFE_API_KEY = 'fake-test-key'
        $global:InvokeJevTestRequests = [System.Collections.Generic.List[object]]::new()
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Headers, $ContentType, $Body, $TimeoutSec, $ConnectionTimeoutSeconds)
            $global:InvokeJevTestRequests.Add([pscustomobject]@{
                Uri = $Uri
                Method = $Method
                Authorization = $Headers.Authorization
                ContentType = $ContentType
                Body = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
                Timeout = if ($null -ne $ConnectionTimeoutSeconds) { $ConnectionTimeoutSeconds } else { $TimeoutSec }
            })
            [pscustomobject]@{
                model = 'jev-test'
                answers = [pscustomobject]@{ result = [pscustomobject]@{ type = 'noul'; noul = 0.95 } }
                usage = [pscustomobject]@{ input_tokens = 20; output_tokens = 5 }
            }
        }
    }

    AfterAll { $env:TYPESAFE_API_KEY = $script:originalKey; Remove-Variable InvokeJevTestRequests, InvokeJevTestPrompts -Scope Global -ErrorAction SilentlyContinue }

    It 'sends UTF-8 state and typed questions and returns structured answers' {
        $result = & $script:jevPath -Message 'Überprüfung 日本語' -Role 'Is this relevant?' -Model 'jev-latest' -TimeoutSec 30
        $result.result.noul | Should -Be 0.95
        $global:InvokeJevTestRequests.Count | Should -Be 1
        $request = $global:InvokeJevTestRequests[0]
        $request.Uri | Should -Be 'https://api.typesafe.ai/v1/systemone'
        $request.Method | Should -Be 'Post'
        $request.Authorization | Should -Be 'Bearer fake-test-key'
        $request.ContentType | Should -Be 'application/json; charset=utf-8'
        $request.Timeout | Should -Be 30
        $request.Body.state | Should -Be 'Überprüfung 日本語'
        $request.Body.model | Should -Be 'jev-latest'
        $request.Body.questions.result.type | Should -Be 'noul'
        $request.Body.questions.result.instructions | Should -Be 'Is this relevant?'
    }

    It 'joins pipeline lines into one evaluation' {
        @('First line', 'Second line') | & $script:jevPath -Role 'Is this relevant?' | Out-Null
        $global:InvokeJevTestRequests.Count | Should -Be 1
        $global:InvokeJevTestRequests[0].Body.state | Should -Be "First line$([Environment]::NewLine)Second line"
    }

    It 'supports State and Instructions aliases with choice criteria' {
        & $script:jevPath -State 'remote work' -Instructions 'Work arrangement?' -QuestionType Choice -Criteria @{
            remote = 'Remote'; onsite = 'On site'
        } | Out-Null
        $global:InvokeJevTestRequests[0].Body.questions.result.type | Should -Be 'choice'
        $global:InvokeJevTestRequests[0].Body.questions.result.criteria.remote | Should -Be 'Remote'
    }

    It 'preserves the order of score levels' {
        & $script:jevPath -Message 'project' -Role 'Fit?' -QuestionType Score -Criteria @('Poor', 'Partial', 'Strong') | Out-Null
        $global:InvokeJevTestRequests[0].Body.questions.result.criteria -join ',' | Should -Be 'Poor,Partial,Strong'
    }

    It 'supports multiple named questions and a full response' {
        $result = & $script:jevPath -Text 'project' -Questions @{
            remote = @{ type = 'noul'; instructions = 'Fully remote?' }
            fit = @{ type = 'score'; instructions = 'Fit?'; criteria = @('Poor', 'Good') }
        } -Raw
        $result.model | Should -Be 'jev-test'
        $result.usage.input_tokens | Should -Be 20
        $global:InvokeJevTestRequests[0].Body.questions.remote.type | Should -Be 'noul'
        $global:InvokeJevTestRequests[0].Body.questions.fit.type | Should -Be 'score'
    }

    It 'loads the existing Invoke-Jev.token format without exposing the secret' {
        $env:TYPESAFE_API_KEY = ''
        $path = Join-Path $TestDrive 'secrets.json'
        '{"Invoke-Jev":{"token":"fake-file-key"}}' | Set-Content -LiteralPath $path
        $result = & $script:jevPath -Message 'project' -Role 'Relevant?' -SecretsPath $path
        $global:InvokeJevTestRequests[0].Authorization | Should -Be 'Bearer fake-file-key'
        $result | ConvertTo-Json -Depth 10 | Should -Not -Match 'fake-file-key'
    }

    It 'prefers the environment key over the secrets file' {
        & $script:jevPath -Message 'project' -Role 'Relevant?' -SecretsPath (Join-Path $TestDrive 'missing.json') | Out-Null
        $global:InvokeJevTestRequests[0].Authorization | Should -Be 'Bearer fake-test-key'
    }

    It 'rejects missing credentials before sending a request' {
        $env:TYPESAFE_API_KEY = ''
        { & $script:jevPath -Message 'project' -Role 'Relevant?' -SecretsPath (Join-Path $TestDrive 'missing.json') } |
            Should -Throw '*Set TYPESAFE_API_KEY*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'rejects missing input before sending a request' {
        { & $script:jevPath -Role 'Relevant?' } | Should -Throw '*Supply -Message*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'rejects invalid criteria before sending a request' -TestCases @(
        @{ Type = 'Choice'; Levels = @('Poor', 'Good') }
        @{ Type = 'Score'; Levels = @{ low = 'Poor'; high = 'Good' } }
        @{ Type = 'Noul'; Levels = 'invalid' }
    ) {
        param($Type, $Levels)
        { & $script:jevPath -Message 'project' -Role 'Relevant?' -QuestionType $Type -Criteria $Levels } | Should -Throw '*criteria*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'evaluates interactive inputs independently and stops on exit' {
        $global:InvokeJevTestPrompts = [System.Collections.Generic.Queue[string]]::new()
        $global:InvokeJevTestPrompts.Enqueue('second project')
        $global:InvokeJevTestPrompts.Enqueue('exit')
        Mock Read-Host { $global:InvokeJevTestPrompts.Dequeue() }
        $results = @(& $script:jevPath -Message 'first project' -Role 'Relevant?' -Interactive)
        $results.Count | Should -Be 2
        $global:InvokeJevTestRequests[0].Body.state | Should -Be 'first project'
        $global:InvokeJevTestRequests[1].Body.state | Should -Be 'second project'
        $global:InvokeJevTestRequests[1].Body.PSObject.Properties.Name | Should -Not -Contain 'messages'
    }

    It 'sanitizes connection errors without forwarding secrets' {
        Mock Invoke-RestMethod { throw 'Connection failed: Bearer fake-test-key' }
        $caught = $null
        try { & $script:jevPath -Message 'project' -Role 'Relevant?' } catch { $caught = $_ }
        $caught.Exception.Message | Should -Match 'TypeSafe request failed'
        $caught.Exception.Message | Should -Not -Match 'fake-test-key'
    }

    It 'reports insufficient credits without forwarding the server body' {
        Mock Invoke-RestMethod {
            $exception = [System.Exception]::new('private server response')
            $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 402 })
            throw $exception
        }
        { & $script:jevPath -Message 'project' -Role 'Relevant?' } | Should -Throw '*HTTP 402*available credits*'
    }
}

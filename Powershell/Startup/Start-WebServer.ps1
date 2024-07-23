[cmdletbinding()]
param(
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="ScriptParameterSet")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Expression,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [int]
    $Port = 8080
)

$job = Start-ThreadJob {
    # Http Server
    $http = [System.Net.HttpListener]::new()

    # Hostname and port to listen on
    $http.Prefixes.Add("http://localhost:$using:Port/")

    # Start the Http Server
    $http.Start()

    # Log ready message to terminal
    if ($http.IsListening) {
        Write-Host -ForegroundColor Cyan "HTTP Server listening on port $using:Port"
    }

    # INFINTE LOOP
    # Used to listen for requests
    while ($http.IsListening) {
        # Get Request Url
        # When a request is made in a web browser the GetContext() method will return a request object
        # Our route examples below will use the request object properties to decide how to respond
        $context = $http.GetContext()


        if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/') {
            Write-Host -ForegroundColor Cyan "$($context.Request.HttpMethod) $($context.Request.RawUrl)"

            try {
                $text = Invoke-Expression $using:Expression | ConvertTo-Json
                Write-Host $text

                #resposed to the request
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($text)
                $context.Response.ContentLength64 = $buffer.Length
                $context.Response.OutputStream.Write($buffer, 0, $buffer.Length) #stream to broswer
                $context.Response.OutputStream.Close() # close the response
            } catch {
                Write-Error $_
            }
        }
    }
}

[console]::TreatControlCAsInput = $true
while (1) {
    if($Host.UI.RawUI.KeyAvailable -and (3 -eq [int]$Host.UI.RawUI.ReadKey("AllowCtrlC,IncludeKeyUp,NoEcho").Character)) {
        $job2 = Start-ThreadJob {
            Start-Sleep -Milliseconds 100
            Invoke-WebRequest "http://localhost:$using:Port/"
        }
        Stop-Job $job -PassThru | Remove-Job
        Stop-Job $job2 -PassThru | Remove-Job
        [console]::TreatControlCAsInput = $true
        throw "HTTP Server shutdown"
        exit
    } else {
        Receive-Job $job
    }
}


    [CmdletBinding(DefaultParameterSetName='RandomNumberParameterSet', HelpUri='https://go.microsoft.com/fwlink/?LinkID=2097016', RemotingCapability='None')]
    param(
        [ValidateNotNull()]
        [System.Nullable[int]]
        ${SetSeed},

        [Parameter(ParameterSetName='DateParameterSet')]
        [Parameter(ParameterSetName='TimePeriodParameterSet')]
        [Parameter(ParameterSetName='DatePeriodParameterSet')]
        [Parameter(ParameterSetName='RandomNumberParameterSet', Position=0)]
        [System.Object]
        ${Maximum},

        [Parameter(ParameterSetName='DateParameterSet')]
        [Parameter(ParameterSetName='TimePeriodParameterSet')]
        [Parameter(ParameterSetName='DatePeriodParameterSet')]
        [Parameter(ParameterSetName='RandomNumberParameterSet')]
        [System.Object]
        ${Minimum},

        [Parameter(ParameterSetName='RandomListItemParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='ShuffleParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [AllowNull()]
        [System.Object[]]
        ${InputObject},

        [Parameter(ParameterSetName='NameParameterSet')]
        [Parameter(ParameterSetName='FirstNameParameterSet')]
        [Parameter(ParameterSetName='MaleNameParameterSet')]
        [Parameter(ParameterSetName='FemaleNameParameterSet')]
        [Parameter(ParameterSetName='RandomNumberParameterSet')]
        [Parameter(ParameterSetName='RandomListItemParameterSet')]
        [Parameter(ParameterSetName='DateParameterSet')]
        [Parameter(ParameterSetName='DatePeriodParameterSet')]
        [ValidateRange(1, 2147483647)]
        [int]
        ${Count},

        [Parameter(ParameterSetName='ShuffleParameterSet', Mandatory=$true)]
        [switch]
        ${Shuffle},

        # here comes my extension ..
        [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true)]
        [switch]
        ${LastName},

        [Parameter(ParameterSetName='FirstNameParameterSet', Mandatory=$true)]
        [switch]
        ${FirstName},

        [Parameter(ParameterSetName='MaleNameParameterSet', Mandatory=$true)]
        [switch]
        ${MaleName},

        [Parameter(ParameterSetName='FemaleNameParameterSet', Mandatory=$true)]
        [switch]
        ${FemaleName},

        [Parameter(ParameterSetName='TimeParameterSet', Mandatory=$true)]
        [switch]
        ${Time},

        [Parameter(ParameterSetName='TimePeriodParameterSet', Mandatory=$true)]
        [switch]
        ${TimePeriod},

        [Parameter(ParameterSetName='DateParameterSet', Mandatory=$true)]
        [switch]
        ${Date},

        [Parameter(ParameterSetName='DatePeriodParameterSet', Mandatory=$true)]
        [switch]
        ${DatePeriod}

    )
    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }
            
            if(${LastName}) {
                $PSBoundParameters.Remove("LastName") | Out-Null
                $names = "Müller","Schmidt","Schneider","Fischer","Weber","Meyer","Wagner","Becker","Schulz","Hoffmann","Schäfer","Koch","Bauer","Richter","Klein","Wolf","Schröder","Neumann","Schwarz","Zimmermann","Braun","Krüger","Hofmann","Hartmann","Lange","Schmitt","Werner","Schmitz","Krause","Meier","Lehmann","Schmid","Schulze","Maier","Köhler","Herrmann","König","Walter","Mayer","Huber","Kaiser","Fuchs","Peters","Lang","Scholz","Möller","Weiß","Jung","Hahn","Schubert","Vogel","Friedrich","Keller","Günther","Frank","Berger","Winkler","Roth","Beck","Lorenz","Baumann","Franke","Albrecht","Schuster","Simon","Ludwig","Böhm","Winter","Kraus","Martin","Schumacher","Krämer","Vogt","Stein","Jäger","Otto","Sommer","Groß","Seidel","Heinrich","Brandt","Haas","Schreiber","Graf","Schulte","Dietrich","Ziegler","Kuhn","Kühn","Pohl","Engel","Horn","Busch","Bergmann","Thomas","Voigt","Sauer","Arnold","Wolff","Pfeiffer"

                $names | Get-Random @PSBoundParameters |% { 
                    if ((Get-Random -Minimum 0 -Maximum 100) -gt 70) {
                        "$_-$($names | Get-Random)" 
                    } else {
                        $_
                    }
                }
            } elseif(${FirstName} -or ${MaleName} -or ${FemaleName}) {
                $girls = @("Mia","Emilia","Sofia","Sophia","Hannah","Hanna","Emma","Lina","Mila","Lea","Leah","Marie","Ella","Luisa","Louisa","Clara","Klara","Amelie","Frieda","Frida","Emily","Emilie","Ida","Leonie","Lia","Liah","Lya","Mathilda","Matilda","Sophie","Sofie","Anna","Lena","Charlotte","Johanna","Leni","Maja","Maya","Nele","Neele","Lotta","Lara","Lilly","Lilli","Laura","Sarah","Sara","Nora","Elisa","Melina","Mira","Juna","Yuna","Helena","Pia","Elena","Mara","Marah","Victoria","Viktoria","Alina","Luna","Paula","Isabella","Finja","Finnja","Amalia","Marlene","Tilda","Anni","Annie","Anny","Luise","Louise","Pauline","Zoe","Paulina","Carla","Karla","Eva","Olivia","Romy","Thea","Lisa","Isabell","Isabel","Isabelle","Josephine","Josefine","Merle","Fiona","Antonia","Malia","Maria","Lucy","Lucie","Elina","Stella","Melissa","Julia","Rosalie","Carlotta","Karlotta","Katharina","Valentina","Hailey","Haylie","Martha","Marta","Jasmin","Yasmin","Emely","Emelie","Maila","Mayla","Mina","Ronja","Amelia","Elli","Elly","Theresa","Teresa","Amira","Chiara","Kiara","Franziska","Lotte","Milena","Nina","Elisabeth","Leila","Leyla","Magdalena","Alma","Ava","Luana","Annabell","Annabelle","Linda","Malina","Mariella","Amy","Evelyn","Evelin","Eveline","Jana","Jule","Lucia","Rosa","Alessia","Annika","Liana","Zoey","Diana","Edda","Lene","Malea","Alea","Anastasia","Elif","Liya","Marla","Aaliyah","Aliya","Ayla","Ela","Kira","Kyra","Milla","Greta","Ariana","Emmi","Emmy","Helene","Leticia","Letizia","Selina","Alena","Aurelia","Elise","Freya","Hedi","Hedy","Laila","Layla","Aleyna","Alicia","Amina","Liliana","Lilliana","Lynn","Linn","Miriam","Alexandra","Arya","Aylin","Eileen","Aileen","Ayleen","Enna","Hermine","Hilda","Valerie","Carolina","Karolina","Dana","Eliana","Jara","Yara","Leia","Leya","Liv","Lorena","Nala","Nahla","Nelly","Nelli","Vivien","Vivienne","Zeynep","Aliyah","Cataleya","Eleni","Hana","Heidi","Julie","Milana","Naila","Nayla","Adriana","Alice","Alva","Amilia","Bella","Cleo","Dilara","Elin","Esther","Malou","Medina","Selma","Svea","Talia","Thalia","Elsa","Jella","Jette","Linea","Linnea","Melisa","Mona","Sina","Sinah","Vanessa","Ylvi","Ylvie","Celine","Eleonora","Hedda","Helen","Henriette","Holly")
                $boys = @("Leon","Ben","Noah","Finn","Fynn","Paul","Elias","Felix","Luis","Louis","Henry","Henri","Luca","Luka","Emil","Lukas","Lucas","Anton","Jonas","Liam","Maximilian","Jakob","Jacob","Leo","Matteo","Oskar","Oscar","Theo","Max","Moritz","Carl","Karl","Julian","Niklas","Niclas","Lio","Milan","David","Jonathan","Samuel","Alexander","Mika","Hannes","Tim","Rafael","Raphael","Erik","Eric","Jona","Jonah","Linus","Levi","Valentin","Artur","Arthur","Benjamin","Tom","Adrian","Marlon","Mats","Mads","Simon","Leonard","Jan","Theodor","Constantin","Konstantin","Fabian","Philipp","Vincent","Nico","Niko","Jannis","Janis","Yannis","Aaron","Milo","Milow","Adam","Carlo","Karlo","Johann","Maxim","Maksim","Mateo","Matti","Pepe","Gabriel","Joshua","Matheo","Toni","Tony","Fritz","Johannes","Fiete","Julius","Daniel","Till","Jannik","Yannik","Yannick","Yannic","Kilian","Lennard","Lennart","Mattis","Mathis","Matthis","Lenny","Lenni","Nick","Nils","Niels","Levin","Sebastian","Florian","Lasse","Lias","Ludwig","Oliver","Leonardo","Lian","Phil","Emilio","Luke","Luc","Ole","Robin","Bruno","Malik","Sam","Richard","Arian","Benedikt","Curt","Kurt","John","Malte","Miran","Franz","Jannes","Amir","Ilias","Ilyas","Kian","Lars","Leopold","Colin","Collin","Friedrich","Justus","Thilo","Tilo","Timo","Charlie","Charly","Mailo","Michael","Damian","Dominic","Dominik","Elia","Eliah","Jayden","Jaden","Tobias","Willi","Willy","Bela","Christian","Jonte","Lorenz","Luan","Marc","Mark","Mattheo","Emilian","Jasper","Ali","Eddie","Eddy","Joel","Leano","Neo","Arne","Henrik","Hugo","Lion","Silas","Aron","Benno","Brian","Bryan","Connor","Conner","Elian","Elyas","Frederik","Frederic","Kalle","Nicolas","Nikolas","Noel","Bastian","Emir","Hamza","Martin","Michel","Mohammed","Muhammad","Nikita","Alessio","Bennet","Ferdinand","Josef","Joseph","Lennox","Matthias","Tyler","Tayler","Xaver","Clemens","Klemens","Dean","Diego","Enno","Jamie","Joris","Lionel","Piet","Samu","Aiden","Ayden","Georg","Henning","Marlo","Alessandro","Elija","Elijah","Eymen","Gustav","Ibrahim","Keno","Magnus","Marco","Marko","Omer","Edgar","Ian","Jaron","Yaron","Kai","Kay","Korbinian","Lino")
                if (${MaleName}) {
                    $names = $boys
                } elseif (${FemaleName}) {
                    $names = $girls
                } else {
                    $names = $girls + $boys
                }
                
                $PSBoundParameters.Remove("FirstName") | Out-Null
                $PSBoundParameters.Remove("MaleName") | Out-Null
                $PSBoundParameters.Remove("FemaleName") | Out-Null

                $names | Get-Random @PSBoundParameters

            } elseif(${Time}) {
                $PSBoundParameters.Remove("Time") | Out-Null
                (New-Object datetime 1899,12,31).AddHours((Get-Random @PSBoundParameters -Minimum 6 -Maximum 19)).AddMinutes((Get-Random @PSBoundParameters -Minimum 0 -Maximum 59))
            } elseif (${TimePeriod}) {
                if (-not $PSBoundParameters['Minimum']) { $PSBoundParameters.Add('Minimum', 15) }
                if (-not $PSBoundParameters['Maximum']) { $PSBoundParameters.Add('Maximum', 120) }
                $PSBoundParameters.Remove('TimePeriod') | Out-Null
                $diff = Get-Random @PSBoundParameters

                $PSBoundParameters.Remove('Minimum') | Out-Null
                $PSBoundParameters.Remove('Maximum') | Out-Null
                $start= Get-Random -Time @PSBoundParameters
                [pscustomobject]@{
                    start= $start
                    end=   $start.AddMinutes($diff)
                }

            } elseif (${DatePeriod}) {
                if (-not $PSBoundParameters['Minimum']) { $PSBoundParameters.Add('Minimum', 1) }
                if (-not $PSBoundParameters['Maximum']) { $PSBoundParameters.Add('Maximum', 120) }
                $PSBoundParameters.Remove('DatePeriod') | Out-Null

                Get-Random @PSBoundParameters |% {
                    $PSBoundParameters.Remove('Minimum') | Out-Null
                    $PSBoundParameters.Remove('Maximum') | Out-Null
                    $PSBoundParameters.Remove('Count') | Out-Null
                    $start= Get-Random -Date @PSBoundParameters
                    [pscustomobject]@{
                        start= $start
                        end=   $start.AddDays($_)
                    }
                }
            } elseif(${Date}) {
                $PSBoundParameters.Remove("Date") | Out-Null
                if (-not $PSBoundParameters['Minimum']) { $PSBoundParameters.Add('Minimum', -400) }
                if (-not $PSBoundParameters['Maximum']) { $PSBoundParameters.Add('Maximum', 400) }

                Get-Random @PSBoundParameters |% { 
                    (Get-Date).AddDays($_).Date
                }

            } else {
                $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Utility\Get-Random', [System.Management.Automation.CommandTypes]::Cmdlet)
                $scriptCmd = {& $wrappedCmd @PSBoundParameters }
                $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
                $steppablePipeline.Begin($PSCmdlet)
            }

            
        } catch {
            throw
        }
    }

    process
    {
        try {
            if ($null -ne $steppablePipeline) {
                $steppablePipeline.Process($_)
            }
        } catch {
            throw
        }
    }

    end
    {
        try {
            if ($null -ne $steppablePipeline) {
                $steppablePipeline.End()
            }
        } catch {
            throw
        }
    }
    <#

    .ForwardHelpTargetName Microsoft.PowerShell.Utility\Get-Random
    .ForwardHelpCategory Cmdlet

    #>


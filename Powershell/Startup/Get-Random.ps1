
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
                $names = "Müller","Schmidt","Schneider","Fischer","Weber","Meyer","Wagner","Schulz","Becker","Hoffmann","Schäfer","Koch","Richter","Bauer","Klein","Wolf","Schröder","Neumann","Schwarz","Zimmermann","Braun","Hofmann","Krüger","Hartmann","Lange","Schmitt","Werner","Schmitz","Krause","Meier","Lehmann","Schmid","Schulze","Maier","Köhler","Herrmann","Walter","König","Mayer","Huber","Kaiser","Fuchs","Peters","Lang","Scholz","Möller","Weiß","Jung","Hahn","Schubert","Vogel","Friedrich","Günther","Keller","Winkler","Frank","Berger","Roth","Beck","Lorenz","Baumann","Franke","Albrecht","Schuster","Simon","Ludwig","Böhm","Winter","Kraus","Martin","Schumacher","Krämer","Vogt","Otto","Jäger","Stein","Groß","Sommer","Seidel","Heinrich","Haas","Brandt","Schreiber","Graf","Dietrich","Schulte","Kühn","Ziegler","Kuhn","Pohl","Engel","Horn","Bergmann","Voigt","Busch","Thomas","Sauer","Arnold","Pfeiffer","Wolff","Beyer","Seifert","Ernst","Lindner","Hübner","Kramer","Jansen","Franz","Peter","Hansen","Wenzel","Götz","Paul","Riedel","Barth","Kern","Hermann","Nagel","Wilhelm","Ott","Bock","Langer","Grimm","Ritter","Haase","Lenz","Förster","Mohr","Kruse","Schumann","Jahn","Thiel","Kaufmann","Zimmer","Hoppe","Petersen","Fiedler","Berg","Arndt","Marx","Lutz","Fritz","Kraft","Michel","Walther","Böttcher","Schütz","Eckert","Sander","Thiele","Reuter","Reinhardt","Schindler","Ebert","Kunz","Schilling","Schramm","Voß","Nowak","Hein","Hesse","Frey","Rudolph","Fröhlich","Beckmann","Kunze","Herzog","Bayer","Behrens","Stephan","Büttner","Gruber","Adam","Gärtner","Witt","Maurer","Bender","Bachmann","Schultz","Seitz","Geiger","Stahl","Steiner","Scherer","Kirchner","Dietz","Ullrich","Kurz","Breuer","Gerlach","Ulrich","Brinkmann","Fink","Heinz","Löffler","Reichert","Naumann","Böhme","Schröter","Blum","Göbel","Moser","Schlüter","Brunner","Körner","Schenk","Wirth","Wegner","Brand","Wendt","Stark","Schwab","Krebs","Heller","Wolter","Reimann","Rieger","Unger","Binder","Bruns","Döring","Menzel","Buchholz","Ackermann","Rose","Meißner","Janssen","Bartsch","May","Hirsch","Jakob","Schiller","Kopp","John","Hinz","Bach","Pfeifer","Bischoff","Engelhardt","Wilke","Sturm","Hildebrandt","Siebert","Urban","Link","Rohde","Kohl","Linke","Wittmann","Fricke","Köster","Gebhardt","Weiss","Vetter","Freitag","Nickel","Hennig","Rau","Münch","Witte","Noack","Renner","Westphal","Reich","Will","Baier","Kolb","Brückner","Marquardt","Kiefer","Keil","Henning","Heinze","Funk","Lemke","Ahrens","Esser","Pieper","Baum","Conrad","Schlegel","Fuhrmann","Decker","Jacob","Held","Röder","Berndt","Hanke","Kirsch","Neubauer","Hammer","Stoll","Erdmann","Mann","Philipp","Schön","Wiese","Kremer","Bartels","Klose","Mertens","Schreiner","Dittrich","Krieger","Kröger","Krug","Harms","Henke","Großmann","Martens","Heß","Schrader","Strauß","Adler","Herbst","Kühne","Heine","Konrad","Kluge","Henkel","Wiedemann","Albert","Popp","Wimmer","Karl","Wahl","Stadler","Hamann","Kuhlmann","Steffen","Lindemann","Fritsch","Bernhardt","Burkhardt","Preuß","Metzger","Bader","Nolte","Hauser","Blank","Beier","Klaus","Probst","Hess","Zander","Miller","Niemann","Funke","Haupt","Burger","Bode","Holz","Jost","Rauch","Rothe","Herold","Jordan","Anders","Fleischer","Wiegand","Hartung","Janßen","Lohmann","Krauß","Vollmer","Baur","Heinemann","Wild","Brenner","Reichel","Wetzel","Christ","Rausch","Hummel","Reiter","Mayr","Knoll","Kroll","Wegener","Beer","Schade","Neubert","Merz","Schüler","Strobel","Diehl","Behrendt","Glaser","Feldmann","Hagen","Jacobs","Rupp","Geißler","Straub","Hohmann","Römer","Stock","Haag","Meister","Freund","Dörr","Kessler","Betz","Seiler","Altmann","Weise","Metz","Eder","Busse","Mai","Wunderlich","Schütte","Hentschel","Voss","Weis","Heck","Born","Falk","Raab","Lauer","Völker","Bittner","Merkel","Sonntag","Moritz","Ehlers","Bertram","Hartwig","Rapp","Gerber","Zeller","Scharf","Pietsch","Kellner","Bär","Eichhorn","Giese","Wulf","Block","Opitz","Gottschalk","Jürgens","Greiner","Wieland","Benz","Keßler","Steffens","Heil","Seeger","Stumpf","Gross","Bühler","Eberhardt","Hiller","Buck","Weigel","Schweizer","Albers","Heuer","Pape","Hempel","Schott","Schütze","Scheffler","Engelmann","Wiesner","Runge","Geyer","Neuhaus","Forster","Oswald","Radtke","Heim","Geisler","Appel","Weidner","Seidl","Moll","Dorn","Klemm","Barthel","Gabriel","Springer","Timm","Engels","Kretschmer","Reimer","Steinbach","Hensel","Wichmann","Eichler","Hecht","Winkelmann","Heise","Noll","Fleischmann","Neugebauer","Hinrichs","Schaller","Lechner","Brandl","Mack","Gebauer","Siegel","Zahn","Singer","Michels","Schuler","Scholl","Uhlig","Brüggemann","Specht","Bürger","Eggert","Baumgartner","Weller","Schnell","Börner","Brauer","Kohler","Pfaff","Auer","Drescher","Otte","Frenzel","Petzold","Rother","Hagemann","Sattler","Wirtz","Ruf","Schirmer","Sauter","Schürmann","Junker","Walz","Dreyer","Sievers","Haller","Prinz","Stolz","Hausmann","Dick","Lux","Schnabel","Elsner","Kühl","Gerhardt","Klotz","Rabe","Schick","Faber","Riedl","Kranz","Fries","Reichelt","Rösch","Langner","Maaß","Wittig","Geier","Finke","Kasper","Maas","Bremer","Rath","Knapp","Dittmann","Kahl","Volk","Faust","Harder","Biermann","Pütz","Kempf","Mielke","Michaelis","Yilmaz","Abel","Thieme","Schütt","Hauck","Cordes","Eberle","Schaefer","Wehner","Haug","Fritzsche","Kilian","Eggers","Große","Matthes","Reinhold","Paulus","Dürr","Bohn","Thoma","Schober","Koller","Korn","Höhne","Hering","Gerdes","Ullmann","Jensen","Endres","Bernhard","Leonhardt","Eckhardt","Schaaf","Höfer","Junge","Rademacher","Pilz","Hellwig","Knorr","Helbig","Melzer","Lippert","Evers","Bahr","Klinger","Heitmann","Ehrhardt","Heinrichs","Horstmann","Behr","Stöhr","Drews","Rudolf","Sieber","Theis","Groth","Hecker","Weiler","Kemper","Rost","Lück","Claus","Hildebrand","Steinmetz","Götze","Trautmann","Blume","Kurth","Augustin","Nitsche","Janke","Jahnke","Klug","Damm","Heimann","Strauch","Schlosser","Uhl","Böhmer","Ries","Hellmann","Höhn","Hertel","Dreher","Borchert","Huth","Sperling","Just","Stenzel","Kunkel","Lau","Sprenger","Schönfeld","Pohlmann","Heilmann","Wacker","Lehner","Teichmann","Kaminski","Vogl","Gehrke","Hartl","Vogler","Schroeder","Thomsen","Nitschke","Engler","Liedtke","Wille","Starke","Friedrichs","Kirchhoff","Schwarze","Balzer","Reinhard","Heinen","Lotz","Küster","Kretzschmar","Schöne","Clemens","Hornung","Ulbrich","Renz","Hofer","Ruppert","Lohse","Schuh","Amann","Westermann","Stiller","Burmeister","Alt","Hampel","Brockmann","Wessel","Späth","Hoyer","Mader","Bartel","Rößler","Krieg","Grote","Schwarzer","Schweitzer","Scheer","Bosch","Zink","Roos","Wagener","Oppermann","Henze","Lehnert","Seemann","Trapp","Reiß","David","Pfeffer","Grau","Horst","Diekmann","Korte","Rehm","Wilde","Schleicher","Lampe","Grundmann","Veit","Daniel","Eisele","Hafner","Steinert","Sachs","Pfister","Kühnel","Schüller","Klatt","Bischof","Schwabe","Wendel","Tietz","Frick","Buschmann","Steinke","Menke","Baumeister","Kirschner","Loos","Ebner","Kastner","Wolters","Orth","Stange","Becher","Reinke","Brendel","Behnke","Schweiger","Kolbe","Schmidtke","Süß","Rühl","Gläser","Heider","Seibert","Heckmann","Reitz","Baumgart","Riemer","Helm","Knobloch","Wörner","Heyer","Nguyen","Baumgärtner","Grund","Brüning","Ostermann","Cremer","Schauer","Jacobi","Ewald","Fürst","Widmann","Otten","Büchner","Petri","Fritsche","Kock","Ehlert","Kleine","Eckstein","Hacker","Brandes","Buchner","Hagedorn","Keck","Häusler","Muth","Apel","Heuser","Bastian","Kersten","Stamm","Niemeyer","Berthold","Gehrmann","Weinert","Schatz","Hager","Volkmann","Michael","Wieczorek","Wilms","Burghardt","Schultze","Merten","Schwartz","Kling","Rode","Neu","Mende","Thies","Böttger","Schell","Spindler","Pabst","Grün","Weiland","Mühlbauer","Hanisch","Doll","Janzen","Adams","Hermes","Haack","Cramer","Spies","Stern","Kugler","Budde","Jakobs","Scheller","Rösler","Reiser","Jonas","Herr","Ebeling","Wulff","Pauli","Löhr","Lukas","Rahn","Sachse","Köhn","Backhaus","Mahler","Hille","Kowalski","Heidrich","Brück","Gottwald","Heidenreich","Baumgarten","Hamm","Körber","Kübler","Frisch","Hardt","Enders","Bräuer","Seidler","Küpper","Lauterbach","Zeidler","Eckardt","Kreuzer","Schiffer","Schaper","Gehring","Hannemann","Ortmann","Petry","Thiemann","Tiedemann","Grünewald","Johannsen","Scheel","Volz","Kunert","Dieckmann","Bormann","Obermeier","Knauer","Schaub","Eilers","Berner","Pahl","Reinecke","Herz","Henn","Brehm","Hoff","Resch","Ochs","Krohn","Lerch","Raabe","Ehrlich","Hack","Friedl","Reis","Rogge","Meurer","Thelen","Drechsler","Hölscher","Morgenstern","Sommerfeld","Ebel","Kellermann","Rupprecht","Post","Hillebrand","Hill","Paulsen","Grabowski","Bolz","Lorenzen","Welsch","Seibel","Kleinert","Schröer","Jaeger","Wächter","Boldt","Palm","Kratz","Reimers","Pusch","Exner","Dietze","Wüst","Andres","Heide","Kaya","Reichardt","Kummer","Metzner","Grube","Ewert","Grunwald","Habermann","Zorn","Fichtner","Emmerich","Mangold","Reif","Ahlers","Kästner","Küppers","Petermann","Stratmann","Sailer","Schuhmacher","Hoch","Struck","Buchmann","Rauscher","Lüdtke","Wendler","Dreier","Zöller","Bucher","Siegert","Finger","Hopf","Rieck","Friese","Hopp","Sahin","Henrich","Spengler"
                $names | Get-Random @PSBoundParameters | ForEach-Object {
                    if ((Get-Random -Minimum 0 -Maximum 100) -gt 70) {
                        "$_-$($names | Get-Random)"
                    } else {
                        $_
                    }
                }
            } elseif(${FirstName} -or ${MaleName} -or ${FemaleName}) {
                $girls = "Mia","Emilia","Sofia","Sophia","Hannah","Hanna","Emma","Lina","Mila","Lea","Leah","Marie","Ella","Luisa","Louisa","Clara","Klara","Amelie","Frieda","Frida","Emily","Emilie","Ida","Leonie","Lia","Liah","Lya","Mathilda","Matilda","Sophie","Sofie","Anna","Lena","Charlotte","Johanna","Leni","Maja","Maya","Nele","Neele","Lotta","Lara","Lilly","Lilli","Laura","Sarah","Sara","Nora","Elisa","Melina","Mira","Juna","Yuna","Helena","Pia","Elena","Mara","Marah","Victoria","Viktoria","Alina","Luna","Paula","Isabella","Finja","Finnja","Amalia","Marlene","Tilda","Anni","Annie","Anny","Luise","Louise","Pauline","Zoe","Paulina","Carla","Karla","Eva","Olivia","Romy","Thea","Lisa","Isabell","Isabel","Isabelle","Josephine","Josefine","Merle","Fiona","Antonia","Malia","Maria","Lucy","Lucie","Elina","Stella","Melissa","Julia","Rosalie","Carlotta","Karlotta","Katharina","Valentina","Hailey","Haylie","Martha","Marta","Jasmin","Yasmin","Emely","Emelie","Maila","Mayla","Mina","Ronja","Amelia","Elli","Elly","Theresa","Teresa","Amira","Chiara","Kiara","Franziska","Lotte","Milena","Nina","Elisabeth","Leila","Leyla","Magdalena","Alma","Ava","Luana","Annabell","Annabelle","Linda","Malina","Mariella","Amy","Evelyn","Evelin","Eveline","Jana","Jule","Lucia","Rosa","Alessia","Annika","Liana","Zoey","Diana","Edda","Lene","Malea","Alea","Anastasia","Elif","Liya","Marla","Aaliyah","Aliya","Ayla","Ela","Kira","Kyra","Milla","Greta","Ariana","Emmi","Emmy","Helene","Leticia","Letizia","Selina","Alena","Aurelia","Elise","Freya","Hedi","Hedy","Laila","Layla","Aleyna","Alicia","Amina","Liliana","Lilliana","Lynn","Linn","Miriam","Alexandra","Arya","Aylin","Eileen","Aileen","Ayleen","Enna","Hermine","Hilda","Valerie","Carolina","Karolina","Dana","Eliana","Jara","Yara","Leia","Leya","Liv","Lorena","Nala","Nahla","Nelly","Nelli","Vivien","Vivienne","Zeynep","Aliyah","Cataleya","Eleni","Hana","Heidi","Julie","Milana","Naila","Nayla","Adriana","Alice","Alva","Amilia","Bella","Cleo","Dilara","Elin","Esther","Malou","Medina","Selma","Svea","Talia","Thalia","Elsa","Jella","Jette","Linea","Linnea","Melisa","Mona","Sina","Sinah","Vanessa","Ylvi","Ylvie","Celine","Eleonora","Hedda","Helen","Henriette","Holly"
                $boys = "Leon","Ben","Noah","Finn","Fynn","Paul","Elias","Felix","Luis","Louis","Henry","Henri","Luca","Luka","Emil","Lukas","Lucas","Anton","Jonas","Liam","Maximilian","Jakob","Jacob","Leo","Matteo","Oskar","Oscar","Theo","Max","Moritz","Carl","Karl","Julian","Niklas","Niclas","Lio","Milan","David","Jonathan","Samuel","Alexander","Mika","Hannes","Tim","Rafael","Raphael","Erik","Eric","Jona","Jonah","Linus","Levi","Valentin","Artur","Arthur","Benjamin","Tom","Adrian","Marlon","Mats","Mads","Simon","Leonard","Jan","Theodor","Constantin","Konstantin","Fabian","Philipp","Vincent","Nico","Niko","Jannis","Janis","Yannis","Aaron","Milo","Milow","Adam","Carlo","Karlo","Johann","Maxim","Maksim","Mateo","Matti","Pepe","Gabriel","Joshua","Matheo","Toni","Tony","Fritz","Johannes","Fiete","Julius","Daniel","Till","Jannik","Yannik","Yannick","Yannic","Kilian","Lennard","Lennart","Mattis","Mathis","Matthis","Lenny","Lenni","Nick","Nils","Niels","Levin","Sebastian","Florian","Lasse","Lias","Ludwig","Oliver","Leonardo","Lian","Phil","Emilio","Luke","Luc","Ole","Robin","Bruno","Malik","Sam","Richard","Arian","Benedikt","Curt","Kurt","John","Malte","Miran","Franz","Jannes","Amir","Ilias","Ilyas","Kian","Lars","Leopold","Colin","Collin","Friedrich","Justus","Thilo","Tilo","Timo","Charlie","Charly","Mailo","Michael","Damian","Dominic","Dominik","Elia","Eliah","Jayden","Jaden","Tobias","Willi","Willy","Bela","Christian","Jonte","Lorenz","Luan","Marc","Mark","Mattheo","Emilian","Jasper","Ali","Eddie","Eddy","Joel","Leano","Neo","Arne","Henrik","Hugo","Lion","Silas","Aron","Benno","Brian","Bryan","Connor","Conner","Elian","Elyas","Frederik","Frederic","Kalle","Nicolas","Nikolas","Noel","Bastian","Emir","Hamza","Martin","Michel","Mohammed","Muhammad","Nikita","Alessio","Bennet","Ferdinand","Josef","Joseph","Lennox","Matthias","Tyler","Tayler","Xaver","Clemens","Klemens","Dean","Diego","Enno","Jamie","Joris","Lionel","Piet","Samu","Aiden","Ayden","Georg","Henning","Marlo","Alessandro","Elija","Elijah","Eymen","Gustav","Ibrahim","Keno","Magnus","Marco","Marko","Omer","Edgar","Ian","Jaron","Yaron","Kai","Kay","Korbinian","Lino"
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

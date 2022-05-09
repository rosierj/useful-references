#Prerun requirements on each machine, uncomment and install

#Install-Module OktaAPI # [1]

#Install-Script CallOktaAPI # [2]

#Install-Module -Name SqlServer # [3]

#Install-Module -Name Az # [4]

#Install-Module -Name ImportExcel # [5]

 

$workbookPath = 'Template location\TemplateName.xlsx'

$workbook = Import-Excel $workbookPath

$resultsLogPath = 'Logs location\'

$remapPath = 'Remap File location\'

 

 

$prodVariables = @{

    groupId  = 'GroupID for Okta'

    api      = 'API URL'

    instance = 'SQL Instance'

    database = 'SQL DB'

    key      = 'OKTA API Key'

    okta     = 'OKTA Org URL'

}

 

$uatVariables = @{

    groupId  = 'GroupID for Okta'

    api      = 'API URL'

    instance = 'SQL Instance'

    database = 'SQL DB'

    key      = 'OKTA API Key'

    okta     = 'OKTA Org URL'

}

 

$testVariables = @{

    groupId  = 'GroupID for Okta'

    api      = 'API URL'

    instance = 'SQL Instance'

    database = 'SQL DB'

    key      = 'OKTA API Key'

    okta     = 'OKTA Org URL'

}

 

$devVariables = @{

    groupId  = 'GroupID for Okta'

    api      = 'API URL'

    instance = 'SQL Instance'

    database = 'SQL DB'

    key      = 'OKTA API Key'

    okta     = 'OKTA Org URL'

}

 

$resultsArray = @()

 

 

function Okta-NewUser {

   

    [CmdletBinding()]

    Param(

    [Parameter(Mandatory=$True)]

    [Object[]]$env )

 

    Connect-Okta $env.key $env.okta

 

    try {

        if($user.password){

            # create user with password

            $oktaUser = New-OktaUser @{profile = $profile; credentials = @{password = @{value = $user.password}}} $true

        }

        else{

            # create user without password

            $oktaUser = New-OktaUser @{profile = $profile} $true

        }

 

        Write-Host "Created user for"  $user.email -ForegroundColor Green

        $logObject.userCreationStatus="Success"

        }

    catch {

            try {

                    # check if user exists

                    $oktaUser = Get-OktaUser $user.email

                    Write-Host  $user.email" already exists in OKTA!" -ForegroundColor Yellow

                    $logObject.userCreationStatus="Exists"

                }

            catch {

                    #capture error message

                    $logObject.ErrorMessage = $_.Exception.Message

                    $oktaUser = $null

                    $logObject.userCreationStatus="Failed"

                    Write-Host "Failed for "  $user.email -ForegroundColor Red

                  }

            }

 

    if ($oktaUser) {

            try {

                Add-OktaGroupMember $env.groupId $oktaUser.id

                $logObject.groupAssignmentStatus="$($user.group) Success"

                Write-Host "Added user to group" -ForegroundColor Green

            }

            catch {

                $logObject.groupAssignmentStatus = "$($user.group) Failed"

                $logObject.ErrorMessage = $_.Exception.Message

                Write-Host "Failed adding user to group." -ForegroundColor Red

        }

    }

}

 

function Database-NewUser {

   

    [CmdletBinding()]

    Param(

    [Parameter(Mandatory=$True)]

    [Object[]]$env )

 

    #API Request to get Client ID

    $clientId = Invoke-RestMethod -Uri "$($env.api)$($user.lookupCode)"

 

    if ($clientId.value.id -eq $null)

    {

        $logObject.userCreationStatus="$($user.group) Failure"

        $logObject.groupAssignmentStatus="$($user.group) Failure"

        $logObject.ErrorMessage="ClientID not valid"

        $logObject.databaseCreationStatus="$($user.group) Failure"       

        break

    }

   

    else

    {

    #Azure Database user assignment

    #Checking to see if user already exists in database           

    $queryResult = Invoke-Sqlcmd -ServerInstance $env.instance -Database $env.database -AccessToken $access_token -query "SELECT * FROM [user].[user] WHERE Email ='$($user.email)'"

               

 

    if ($queryResult)

    {

        $logObject.databaseCreationStatus="$($user.group) Exists"

        Write-Host   "$($user.email) already exists in Database!" -ForegroundColor Yellow

 

        $currentMapping = Invoke-Sqlcmd -ServerInstance $env.instance -Database $env.database -AccessToken $access_token -query "SELECT * FROM [user].[UserToClient] WHERE UserId ='$($queryResult[0])'"

 
        #If user exists, but the supplied ClientID is different, generates a script to remap the user

        if ($currentMapping[1] -ne $clientId.value.id)

        {

            Write-Host "Requested ClientID is different. Generating remap script." -ForegroundColor Yellow

            "UPDATE [user].[UserToClient] Set ClientID = '$($clientId.value.id)', ClientLookupCode = '$($user.lookupcode)' WHERE UserId = '$($queryResult[0])'" | Out-File -FilePath "$($remapPath)\remap_ssms.txt" -Append

        }

    }

    else

    {

        Invoke-Sqlcmd -ServerInstance $env.instance -Database $env.database -AccessToken $access_token -query "INSERT INTO [user].[user] (FirstName, LastName, Email, IsActive, IsDeleted) VALUES ('$($user.firstName)', '$($user.lastName)', '$($user.email)', '1', '0')"

               

        #grabbing newly created user id

        $newUser = Invoke-Sqlcmd -ServerInstance $env.instance -Database $env.database -AccessToken $access_token -query "SELECT * FROM [user].[user] WHERE Email = '$($user.email)'"

        Invoke-Sqlcmd -ServerInstance $env.instance -Database $env.database -AccessToken $access_token -query "INSERT INTO [user].[UserToClient] (UserId, ClientId, ClientLookupCode) VALUES ('$($newUser.Id)', '$($clientId.value.id)', '$($user.lookupcode)')"

        Invoke-Sqlcmd -ServerInstance $env.instance -Database $env.database -AccessToken $access_token -query "INSERT INTO [user].[UserToReportingRole] (UserId, ReportingRoleId) VALUES ('$($newUser.Id)', '1')"

        Write-Host   "'$($user.email)' successfully added!" -ForegroundColor Green

        $logObject.databaseCreationStatus="$($user.group) Success"

    }

    }

}

 

 

Connect-AzAccount

$access_token = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token

 

       foreach ($user in $workbook)

       {

        #OKTA User Creation and Group Assignment

 

 

        Write-Host "Creating user for"  $user.email

        $profile = @{login = $user.email; email = $user.email; firstName = $user.firstName; lastName = $user.lastName}

        $logObject = [PSCustomObject]@{

            firstName= $user.firstName;

            lastName=$user.lastName;

            login = $user.email;

            userCreationStatus ="";

            groupAssignmentStatus ="";

            ErrorMessage="";

            databaseCreationStatus=""}

           

       

        switch ($user.group)

        {

            Dev  {Database-NewUser -env $devVariables; Okta-NewUser -env $devVariables}

            Test {Database-NewUser -env $testVariables; Okta-NewUser -env $testVariables}

            UAT  {Database-NewUser -env $uatVariables; Okta-NewUser -env $uatVariables}

            Prod {Database-NewUser -env $prodVariables; Okta-NewUser -env $prodVariables}

        }

 

 

        #Logging export to CSV

        $resultsArray += $logObject

      }      

                       

$resultsLogName = "Results_Log_'$(Get-Date -UFormat '%Y%m%d_%H%M%S')'"

 

New-Item -ItemType "directory" -Path "$($resultsLogPath)\$($resultsLogName)"

 
#exports log array as csv
$resultsArray | Export-Csv -Path "$($resultsLogPath)\$($resultsLogName)\$($resultsLogName).csv"

 
#If a remap file exits, this will move it to the log directory. We did not want remapping to happen via automation.
if (Test-Path -Path "$($remapPath)\remap_ssms.txt")

{

    Move-Item -Path "$($remapPath)\remap_ssms.txt" -Destination "$($resultsLogPath)\$($resultsLogName)\"

}

 

Move-Item -Path $workbookPath -Destination "$($resultsLogPath)\$($resultsLogName)\"
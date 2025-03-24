$PublicDataAppToken = Read-Host -Prompt "Enter public data app token"
$tenantId = Read-Host -Prompt "Enter tenant ID"
$certPassword = Read-Host -AsSecureString -Prompt "Enter certificate password"

$appName = "BTJ-GCFHLDeployment2"
$certPathRoot = "$($HOME)\documents"
$certStoreLocation = "cert:\CurrentUser\My"
$certProvider = "Microsoft Enhanced RSA and AES Cryptographic Provider"
$certDescription = "Used to access Microsoft Graph PowerShell SDK"
$certFileNamePFX = "BTJ-GCFHLDeployment2.pfx"
$certFileNameCRT = "BTJ-GCFHLDeployment2.crt"
$certSubject = "cn=BTJ-GCFHLDeployment2"

$externalConnectionId = "WAStateEVData3"
$externalConnectionName = "WA State Electric Vehicle Population Data"
$externalConnectionDescription = "This dataset shows the Battery Electric Vehicles (BEVs) and Plug-in Hybrid Electric Vehicles (PHEVs) that are currently registered through Washington State Department of Licensing (DOL)."


# main function calls
$certThumbprint = CreateSelfSignedCertificate -certPassword $certPassword
$newApp = CreateGraphAppRegistration -tenantId $tenantId -appName $appName -certFileNamePFX $certFileNamePFX -certPassword $certPassword
$clientId = $($newApp.AppId)
$consentAppPermissionsUri = "https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$clientId"
Start-Process "msedge.exe" $consentAppPermissionsUri
CreateGraphConnector -tenantId $tenantId -certThumbprint $certThumbprint -externalConnectionId $externalConnectionId -externalConnectionName $externalConnectionName -externalConnectionDescription $externalConnectionDescription

$results = GetWAEVData -appToken $PublicDataAppToken
$results | ForEach-Object -Parallel {
    IngestWAEVData -externalConnectionId $using:externalConnectionId -inputItem $_
} -ThrottleLimit 20


function GetWAEVData {
    param (
        [string]$appToken
    )
    $url = "https://data.wa.gov/resource/f6w7-q2d2"

    # set headers to accept JSON and app token
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept","application/json")
    $headers.Add("X-App-Token",$appToken)

    # get data from WA State EV data
    $results = Invoke-RestMethod -Uri $url -Method get -Headers $headers

    return $results
}


function CreateSelfSignedCertificate {
    param (
        [SecureString]$certPassword
    )
    #create self-signed certificate
    $ssc = New-SelfSignedCertificate -CertStoreLocation $certStoreLocation -Provider $certProvider `
                            -Subject $certSubject -KeyDescription $certDescription `
                            -NotBefore (Get-Date).AddDays(-1) -NotAfter (Get-Date).AddYears(2)

    # Export certificate to PFX - uploaded to Azure AD application registration
    Export-PfxCertificate -cert $certStoreLocation\$($ssc.Thumbprint) -FilePath (Join-Path -Path $certPathRoot -ChildPath "$certFileNamePFX") -Password $certPassword -Force

    # Export certificate to CRT - imported into the Service Principal / enterprise application
    Export-Certificate -Cert $certStoreLocation\$($ssc.Thumbprint) -FilePath (Join-Path -Path $certPathRoot -ChildPath "$certFileNameCRT") -Force

    return $ssc.Thumbprint
}

function CreateGraphAppRegistration {
    param (
        [string]$tenantId,
        [SecureString]$certPassword,
        [string]$certFileNamePFX,
        [string]$appName
    )
    $GraphResourceId = "00000003-0000-0000-c000-000000000000"
    $ExternalConnectionReadWriteOwnedBy = @{ Id = "f431331c-49a6-499f-be1c-62af19c34a9d"; Type = "Role" }
    $ExternalItemReadWriteOwnedBy = @{ Id = "8116ae0f-55c2-452d-9944-d18420f5b2c8"; Type = "Role" }
    $UserReadAll = @{ Id = "df021288-bdef-4463-88db-98f22de89214"; Type = "Role" }

    #create new application registration
    $KeyStorageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $certFile = Get-ChildItem -Path $certFileNamePFX
    $x509 =  New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2($certFile.FullName, $certPassword, $KeyStorageFlags)
    $certValueRaw = $x509.GetRawCertData()

    # https://docs.microsoft.com/en-us/graph/api/resources/keycredential?view=graph-rest-1.0
    $keyId = [guid]::NewGuid()

    $keyCredential = New-Object -TypeName "Microsoft.Graph.PowerShell.Models.MicrosoftGraphKeyCredential"
    $keyCredential.StartDateTime = $x509.NotBefore
    $keyCredential.EndDateTime = $x509.NotAfter
    $keyCredential.KeyId = $keyId
    $keyCredential.Type = "AsymmetricX509Cert"
    $keyCredential.Usage = "Verify"
    $keyCredential.Key = $certValueRaw

    #connect to Microsoft Graph with delegated permissions to create new app registration and associated service principal
    Connect-Graph -Scopes Application.ReadWrite.All -TenantId $tenantId
    $newApp = New-MgApplication -KeyCredentials $keyCredential -DisplayName $appName -SignInAudience "AzureADMyOrg" -RequiredResourceAccess @{ ResourceAppId = $graphResourceId; resourceAccess = $UserReadAll,$ExternalConnectionReadWriteOwnedBy,$ExternalItemReadWriteOwnedBy }
    New-MgServicePrincipal -AppId $newApp.AppId

    #verify connection successful with AppOnly using AppId / ClientId of newly created application
    #$certThumbprint = Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -EQ $certSubject | Select-Object -ExpandProperty Thumbprint
    #Connect-Graph -CertificateThumbprint $certThumbprint -ClientId $newApp.AppId -TenantId $tenantId -ForceRefresh

    return $newApp
}

function CreateGraphConnector {
    param (
        [string]$tenantId,
        [string]$certThumbprint,
        [string]$externalConnectionId,
        [string]$externalConnectionName,
        [string]$externalConnectionDescription
    )    
    Connect-MgGraph -clientId $ -TenantId $tenantId -CertificateThumbprint $certThumbprint

    # schema for GCs
    $params = @{
        baseType = "microsoft.graph.externalItem"
        properties = @(
            @{
                name = "id"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "false"
                isRefinable = "false"
            }
            @{
                name = "title"
                type = "string"
                isSearchable = "true"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "false"
                labels = @(
                    "title"
                )
            }
            @{
                name = "vin"
                type = "string"
                isSearchable = "true"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "false"
            }
            @{
                name = "county"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "city"
                type = "dateTime"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "state"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "postalCode"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "url"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "false"
                isRefinable = "false"
                labels = @(
                    "url"
                )
            }
            @{
                name = "modelYear"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "make"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "model"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "electricVehicleType"
                type = "string"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "true"
            }
            @{
                name = "electricRange"
                type = "int64"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "false"
            }
            @{
                name = "baseMSRP"
                type = "int64"
                isSearchable = "false"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "false"
            }
            @{
                name = "DOLVehicleID"
                type = "string"
                isSearchable = "true"
                isRetrievable = "true"
                isQueryable = "true"
                isRefinable = "false"
            }
        )
    }

    # Create the external connection if it doesn't exist
    if(!(Get-MgExternalConnection -ExternalConnectionId $externalConnectionId -ErrorAction SilentlyContinue))
    {
        New-MgExternalConnection -Name $externalConnectionName -Id $externalConnectionId -Description $externalConnectionDescription
        Update-MgExternalConnectionSchema -ExternalConnectionId $externalConnectionId -BodyParameter $params
    }
}

function IngestWAEVData {
    param (
        [string]$externalConnectionId,
        [object]$inputItem
    )

    $itemParams = @{
        acl = @(
            @{
                type = "everyone"
                value = "everyone"
                accessType = "grant"
            }
        )
        properties = @{
            id = "$($inputItem.dol_vehicle_id)"
            baseMSRP = $inputItem.base_msrp
            electricRange = $inputItem.electric_range
            electricVehicleType = $inputItem.ev_type
            make = $inputItem.make
            model = $inputItem.model
            modelYear = $inputItem.model_year
            vin = $inputItem.vin_1_10
            title = $inputItem.dol_vehicle_id
            url = ""
            county = $inputItem.county
            city = $inputItem.city
            state = $inputItem.state
            postalCode = $inputItem.zip_code
            DOLVehicleID = $inputItem.dol_vehicle_id
        }
    }

    # items should not be updated in source, so skip if item exists in Graph connector already
    if(!(Get-MgExternalConnectionItem -ExternalConnectionId $externalConnectionId -ExternalItemId $itemParams.properties.id.ToString() -ErrorAction SilentlyContinue))
    {
        Write-Output "Adding missing item $($itemParams.properties.id.ToString())"
        Set-MgExternalConnectionItem -ExternalConnectionId $externalConnectionId -ExternalItemId $itemParams.properties.id.ToString() -BodyParameter $itemParams
    }
}



# remove sample items if needed
<#
$results[801..1000] | ForEach-Object -Parallel {
    Write-Output "Removing item $($_.dol_vehicle_id)"
    Remove-MgExternalConnectionItem -ExternalConnectionId $using:externalConnectionId -ExternalItemId $_.dol_vehicle_id
} -ThrottleLimit 20
#>
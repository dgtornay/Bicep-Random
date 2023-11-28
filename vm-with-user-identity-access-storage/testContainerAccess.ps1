Connect-AzAccount -Identity
$context = New-AzStorageContext -UseConnectedAccount -StorageAccountName "sadavidt3s2zwikxosd4"
Get-AzStorageBlob -Context $context -Container "container"
Get-AzStorageBlobContent -Context $context -Container "container" -Blob "3gry5ydf7.jpg" -Destination D:\
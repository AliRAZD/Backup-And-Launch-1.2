

 ############################################################   
	       #Backup And Launch 
		       #Version 1.2
       #Author: Michal "Ali" Kawczynski
############################################################	   
	   


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


$configFilePath = Join-Path -Path $PSScriptRoot -ChildPath "Settings.json"


function Load-Config {
    if (Test-Path $configFilePath) {
        try {
            # Deserializacja JSON do obiektu PowerShell
            $jsonContent = Get-Content $configFilePath | ConvertFrom-Json
            return $jsonContent
        } catch {
            Write-Error "Błąd podczas wczytywania pliku JSON: $_"
            return $null
        }
    }
    return $null  
}


function Save-Config {
    param (
        [PSCustomObject]$configData
    )
    
    $configData | ConvertTo-Json -Depth 3 | Set-Content -Path $configFilePath
}


function Show-FileSelectionDialog {
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $fileDialog.Title = "SELECT FILES TO BACKUP"
    $fileDialog.Multiselect = $true  # Zezwól na wybór wielu plików
    $fileDialog.Filter = "All Files (*.*)|*.*"
    if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $fileDialog.FileNames
    }
    return @()
}


function Show-SelectedFilesDialog {
    param (
        [array]$files
    )

    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Selected Files for Backup"
    $form.Width = 400
    $form.Height = 300
    $form.StartPosition = "CenterScreen"

    
    $fileListBox = New-Object System.Windows.Forms.ListBox
    $fileListBox.Width = 350
    $fileListBox.Height = 200
    $fileListBox.Top = 20
    $fileListBox.Left = 20
    $fileListBox.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
    $fileListBox.Items.AddRange($files)
	
	$removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Text = "Remove Selected"
    $removeButton.Width = 110
    $removeButton.Top = 230
    $removeButton.Left = 250
    $removeButton.Add_Click({
    $selectedItems = $fileListBox.SelectedItems
    foreach ($item in $selectedItems) {
        $fileListBox.Items.Remove($item)
    }
})
$form.Controls.Add($removeButton)


    
    $addButton = New-Object System.Windows.Forms.Button
    $addButton.Text = "Add Files"
    $addButton.Width = 75
    $addButton.Top = 230
    $addButton.Left = 50
    $addButton.Add_Click({
        $newFiles = Show-FileSelectionDialog
        if ($newFiles.Count -gt 0) {
            $fileListBox.Items.AddRange($newFiles)
        }
    })

    
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Width = 75
    $okButton.Top = 230
    $okButton.Left = 150
    $okButton.Add_Click({
        $form.Close()
    })

    
    $form.Controls.Add($fileListBox)
    $form.Controls.Add($addButton)
    $form.Controls.Add($okButton)

    
    $form.ShowDialog()

    
    return $fileListBox.Items
}


$maxBackups = 2


$config = Load-Config




if ($null -eq $config) {
    
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "SELECT FOLDER FOR BACKUPS"
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $backupFolder = $folderDialog.SelectedPath
    } else {
        Write-Error "No backup folder selected. Exiting."
        exit
    }

    
    $selectedFiles = Show-FileSelectionDialog

    if ($selectedFiles.Count -eq 0) {
        Write-Error "No files selected for backup. Exiting."
        exit
    }

    
    $selectedFilesForBackup = Show-SelectedFilesDialog -files $selectedFiles

    if ($selectedFilesForBackup.Count -eq 0) {
        Write-Error "No files selected after confirmation. Exiting."
        exit
    }

    
    $appDialog = New-Object System.Windows.Forms.OpenFileDialog
    $appDialog.Title = "SELECT THE APPLICATION TO LAUNCH"
    $appDialog.Filter = "Executable Files (*.exe)|*.exe"
    
    if ($appDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $appPath = $appDialog.FileName
    } else {
        Write-Error "No application selected. Exiting."
        exit
    }

    
    $config = [PSCustomObject]@{
        backupFolder = $backupFolder
        files = $selectedFilesForBackup
        appPath = $appPath
    }

    
    Save-Config -configData $config
} else {
    
    $backupFolder = $config.backupFolder
    $sourceFiles = $config.files
    $appPath = $config.appPath
}


Write-Output "Backup folder: $backupFolder"
Write-Output "Files selected for backup:"
$sourceFiles


$logFile = Join-Path -Path $backupFolder -ChildPath "backup_log.txt"


function Log-Message {
    param (
        [string]$level,
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$level] - $message"
    Add-Content -Path $logFile -Value "`n==== $timestamp ==== `n$logEntry"
}


function Backup-FileWithProgress {
    param (
        [string]$sourceFile,
        [string]$backupFolder,
        [int]$maxBackups,
        [System.Windows.Forms.ProgressBar]$progressBar,
        [System.Windows.Forms.Label]$label
    )

    if (-not (Test-Path $sourceFile)) {
        Log-Message -level "WARNING" -message "The file does not exist: $sourceFile"
        return
    }

    try {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile)
        $fileExtension = [System.IO.Path]::GetExtension($sourceFile)
        $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $backupFileName = "$fileName-$timestamp$fileExtension"
        $backupFilePath = Join-Path $backupFolder $backupFileName

        # Aktualizacja labela przed kopiowaniem
        $label.Text = "Backing up: $fileName"
        [System.Windows.Forms.Application]::DoEvents()

        # Kopiowanie pliku
        Copy-Item -Path $sourceFile -Destination $backupFilePath -Force
        Log-Message -level "INFO" -message "The file has been backed up: $sourceFile to $backupFilePath"

        # Aktualizacja paska postępu
        $progressBar.PerformStep()
        $percentage = [math]::Round(($progressBar.Value / $progressBar.Maximum) * 100, 2)
        $label.Text = "Backup Progress: $percentage% - Last file: $fileName"

        # Pobranie wszystkich istniejących kopii tego pliku (dokładny wzorzec)
        $backupFiles = Get-ChildItem -Path $backupFolder -Filter "$fileName-*$fileExtension" |
                       Sort-Object CreationTime

        # Usuwanie najstarszych, jeśli jest ich za dużo
        if ($backupFiles.Count -gt $maxBackups) {
            $filesToRemove = $backupFiles | Select-Object -First ($backupFiles.Count - $maxBackups)
            foreach ($fileToRemove in $filesToRemove) {
                try {
                    Remove-Item $fileToRemove.FullName -Force
                    Log-Message -level "INFO" -message "Deleted old backup: $($fileToRemove.FullName)"
                } catch {
                    Log-Message -level "ERROR" -message "Failed to delete old backup: $($fileToRemove.FullName). Details: $_"
                }
            }
        }

    } catch {
        Log-Message -level "ERROR" -message "File backup error: $sourceFile. Details: $_"
    }
}




$form = New-Object System.Windows.Forms.Form
$form.Text = "Creating Backup"
$form.Width = 450
$form.Height = 200
$form.StartPosition = "CenterScreen"

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Minimum = 0
$progressBar.Maximum = $sourceFiles.Count
$progressBar.Step = 1
$progressBar.Width = 400
$progressBar.Height = 25
$progressBar.Top = 50
$progressBar.Left = 20


$label = New-Object System.Windows.Forms.Label
$label.Text = "Starting backup..."
$label.Top = 90
$label.Left = 20
$label.Width = 400

$form.Controls.Add($progressBar)
$form.Controls.Add($label)
$form.Show()


foreach ($sourceFile in $sourceFiles) {
    Backup-FileWithProgress -sourceFile $sourceFile -backupFolder $backupFolder -maxBackups $maxBackups -progressBar $progressBar -label $label
    [System.Windows.Forms.Application]::DoEvents()  
    Start-Sleep -Seconds 1  
}


$form.Close()


Start-Process $appPath
















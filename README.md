# Notion to Google Sheets Synchronization Script
This script is designed to sync data from a Notion database to a Google Sheet. The script fetches entries from a Notion database and updates them to a designated Google Sheet using gcloud, jq, and the Notion and Google Sheets APIs.

## Requirements
* [gloucd](https://cloud.google.com/sdk/docs/install?hl=de#linux)
* [jq](https://jqlang.github.io/jq/download/)

## Features
* Pulls data from a Notion database and formats it for a Google Sheet.
* Allows for the synchronization of data between a Notion database and a Google Sheet.
* Checks if the script is run as root and requests root permissions if not.
* Generates a JWT and uses it to obtain an access token from Google.
* Updates the Google Sheet with data from the Notion database.
* If no configuration is found, it prompts for user input to create one.

## Initial Setup
* Run the script once. It will check if a configuration.json file exists in the same directory.
* If the configuration.json file doesn't exist, it will ask for the Notion API key, Notion database ID, Google Sheets ID, and the Google Sheets range (e.g., Sheet1!A1). A new configuration.json file will be created with these inputs.
* Make sure the script has permissions to access the Google Sheets API with the correct credentials.

## Known Issues
If you might have troubles executing the script `main.sh`, it might be because the line endings werent correctly submitted to git. In this case, run the following command to replace the line endings:
```
sed -i 's/\r$//' main.sh
```

## Warning
Remember not to share your Notion API key or Google Sheets spreadsheet ID in a public space. Keep your configuration.json file in a secure location, as it contains sensitive data.

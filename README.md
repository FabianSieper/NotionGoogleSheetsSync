# Notion to Google Sheets Synchronization Script
This script is designed to sync data from a Notion database to a Google Sheet. The script fetches entries from a Notion database and updates them to a designated Google Sheet using gcloud, jq, and the Notion and Google Sheets APIs.

## Requirements
* [gloucd](https://cloud.google.com/sdk/docs/install?hl=de#linux)
* [jq](https://jqlang.github.io/jq/download/)

## Usage
Either run
```
.\main.sh
```
In order to retrieve all entries from a Notion database. It has to be kept in mind, that only a maximum of 100 is returned by the default Notion request.

To filter the entries of the Notion database you can run
```
.\main.sh column_name content_to_filter_for
```
Here, it is filter for column_name = content_to_filter_for. Filter can only be applied to "text", "single-select", "multi-select" or "title" columns.

It is also possible to change the Google Sheet tab name after the configuration-phase while executing the script. Simply enter the name of the Google Sheet tab as the third parameter. This will overwrite the set Sheet tab name for the current run.
```
./main.sh Summary "Summary of Notion Entry" Page2
```

Further examples:
```
# Query for relation-page names. 
# This requires a separate formula-column, which calculates the bare name of the related pages
./main.sh relation_name_formula_column related_page
```

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

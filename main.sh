#!/bin/bash

# -------------------------------------------------------------------------
# Requirements for this script to work:
# * gcloud: https://cloud.google.com/sdk/docs/install?hl=de#linux
# * jq:     https://jqlang.github.io/jq/download/
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Definition of functions
# -------------------------------------------------------------------------
run_as_root() {
    # Check if the script is running as root, if not then it will ask for root permission
    if [ "$EUID" -ne 0 ]
        then echo "Please run as root"
        sudo "$0" "$@"
        exit
    fi
}

get_script_path() {
    script_path="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
    echo "$script_path"
}

# get_all_notion_entries "$NOTION_API_KEY" "$DATABASE_ID"
get_all_notion_entries() {

    local notion_api_key="$1"
    local database_id="$2"
    local filter_field="$3"
    local filter_value="$4"

    if [[ -z "$filter_field" || -z "$filter_value" ]]; then

        curl -X POST 'https://api.notion.com/v1/databases/'"${database_id}"'/query' \
            -H 'Authorization: Bearer '"$notion_api_key"'' \
            -H 'Notion-Version: 2022-06-28' | jq

    else

        curl -X POST 'https://api.notion.com/v1/databases/'"${database_id}"'/query' \
            -H 'Authorization: Bearer '"$notion_api_key"'' \
            -H 'Notion-Version: 2022-06-28' \
            -H "Content-Type: application/json" \
            -d '{
                "filter": {
                    "or": [
                        {
                            "property": "'"$filter_field"'",
                            "rich_text": {
                                "equals": "'"$filter_value"'"
                            }
                        }
                    ]
                    
                }
            }' | jq
    fi
}

update_google_sheet() {
    local spreadsheet_id="$1"
    local range="$2"
    local data="$3" # data should be in the form of list of lists, each representing a row
    
    # Load the service account key into a variable
    credentials=$(cat $GOOGLE_APPLICATION_CREDENTIALS)

    # Extract the private key and save it in a variable
    private_key=$(echo $credentials | jq -r .private_key)

    # Extract the client email and save it in a variable
    client_email=$(echo $credentials | jq -r .client_email)

    # Generate a JWT header and save it in a variable
    header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e | tr -d '\n' | tr -d '=' | tr '/+' '_-')

    # Generate a JWT claim set and save it in a variable
    now=$(date +%s)
    claim_set=$(echo -n '{"iss":"'"${client_email}"'","scope":"https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/drive","aud":"https://oauth2.googleapis.com/token","exp":'$(($now + 3600))',"iat":'"$now"' }' | openssl base64 -e | tr -d '\n' | tr -d '=' | tr '/+' '_-')

    # Generate a JWT signature and save it in a variable
    signature=$(echo -n "${header}.${claim_set}" | openssl dgst -binary -sha256 -sign <(echo -n "$private_key") | openssl base64 -e | tr -d '\n' | tr -d '=' | tr '/+' '_-')

    # Combine the header, claim set, and signature into a JWT
    jwt="${header}.${claim_set}.${signature}"

    # Use the JWT to obtain an access token from Google
    access_token=$(curl -s -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}" https://oauth2.googleapis.com/token | jq -r .access_token)

    curl -X PUT \
    "https://sheets.googleapis.com/v4/spreadsheets/${spreadsheet_id}/values/${range}?valueInputOption=USER_ENTERED" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d '{
        "range": "'"${range}"'",
        "majorDimension": "ROWS",
        "values": '"${data}"'
    }'
}

get_absolute_path() {
    local filename="$1"

    # Check if file exists in the current working directory
    if [ -f "$filename" ]; then
        # Use pwd and append the filename to get the absolute path
        local abs_path="$(get_script_path)/$filename"
        echo $abs_path
    else
        return 1
    fi
}

get_script_dir() {
    script_dir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
    echo $script_dir
}

get_credentials_path() {
    # Get the path of the current script
    local script_dir=$(get_script_dir)

    # Append /credentials.json to get the credentials path
    local credentials_path="${script_dir}/credentials.json"

    # Print the credentials path
    printf "${credentials_path}"
}

get_configuration_path() {
    # Get the path of the current script
    local script_dir=$(get_script_dir)

    # Append /credentials.json to get the credentials path
    local credentials_path="${script_dir}/configuration.json"

    # Print the credentials path
    printf "${credentials_path}"
}

set_credentials() {
    local credentials_path=$(get_credentials_path)
    
    if [[ ! -f "$credentials_path" ]]; then
        echo "'${credentials_path}' file does not exist. Creating one now..."

        echo "Please follow the instructions to download the credentials file for Google"
        echo "These steps only have to be performed once:"
        echo "1. Visit the site https://console.developers.google.com"
        echo "2. Create a new project and give it a name"
        echo "3. Click on 'Enable APIs and Services'"
        echo "4. Find and enable the 'Google Sheet API"
        echo "5. Select 'Credentials' on the left hand side"
        echo "6. Select 'Create credentials' at the upper side of the page"
        echo "7. Select 'Create Service Account'"
        echo "8. Add role 'Editor' for the manipulation of Google Sheets"
        echo "9. Click 'Continue' and 'Done'"
        echo "10. Click on the newly created 'Service Accounts'-row"
        echo "11. Switch to tab 'Keys', click 'Add Key' > 'Create new key'"
        echo "12. Choose 'JSON' as the key type and click 'Create'"
        echo "13. Open the Google Sheet you want to use for your sync"
        echo "14. Click 'Share', enter the email contained in the downloaded .json file and choose the role 'Editor'"
        echo "15. Copy the content of the downloaded .json file beneath this line"

        credentials=""
        while IFS= read -r line; do
            credentials+="${line}"
            # Check if the line ends with "}"
            if [[ "${line}" == "}" ]]; then
                break
            fi
        done

        echo "${credentials}" > "${credentials_path}" 
        echo "Content was written to file ${credentials_path}"
        export GOOGLE_APPLICATION_CREDENTIALS="$credentials_path"

    else
        echo "Crdentials file '${credentials_path}' was found."
        echo "Extracting information from credentials file ..."
        export GOOGLE_APPLICATION_CREDENTIALS=${credentials_path}
    fi
}

transform_notion_data_to_sheet_data() {
    # The first argument is the JSON output from the Notion API
    local json_output="$1"

    # Use 'jq' to extract the desired values
    local name_values=$(echo $json_output | jq -r '.results[].properties.Name.title[].text.content')
    local data_values=$(echo $json_output | jq -r '.results[].properties.Data.rich_text[].text.content')

    # Convert 'name_values' and 'data_values' into arrays
    local name_values_array=($name_values)
    local data_values_array=($data_values)

    # Initialize 'data' as an empty array
    declare -a data

    # Loop over the indices of 'name_values_array'
    for i in "${!name_values_array[@]}"; do
        # Get the corresponding 'name_value' and 'data_value'
        local name_value="${name_values_array[i]}"
        local data_value="${data_values_array[i]}"

        # Append a new list containing 'name_value' and 'data_value' to 'data'
        # Note: the strings are now quoted
        data+=("[\"$name_value\",\"$data_value\"]")
    done

    # Convert 'data' into a string that can be passed to 'update_google_sheet'
    local data_string="[$(IFS=,; echo "${data[*]}")]"

    # Return 'data_string'
    echo "$data_string"
}

get_or_prompt_for_configuration() {
    CONFIGURATION_FILE=$(get_configuration_path)

    if [ ! -f "$CONFIGURATION_FILE" ]; then
        read -p "Enter your Notion API Key: " NOTION_API_KEY
        read -p "Enter your Database ID: " DATABASE_ID
        read -p "Enter your Spreadsheet ID: " SPREADSHEET_ID
        read -p "Enter your Range (e.g. Sheet1!A1): " RANGE

        # Create secrets.json
        echo "Creating configuration file '${CONFIGURATION_FILE}'" >&2
        cat <<EOF >$CONFIGURATION_FILE
{
    "NOTION_API_KEY": "$NOTION_API_KEY",
    "DATABASE_ID": "$DATABASE_ID",
    "SPREADSHEET_ID": "$SPREADSHEET_ID",
    "RANGE": "$RANGE"
}
EOF
    else
        echo "Configuration file '${CONFIGURATION_FILE}' was found" >&2
        echo "Extracting information ..." >&2

        # Extract values from secrets.json
        NOTION_API_KEY=$(jq -r '.NOTION_API_KEY' $CONFIGURATION_FILE)
        DATABASE_ID=$(jq -r '.DATABASE_ID' $CONFIGURATION_FILE)
        SPREADSHEET_ID=$(jq -r '.SPREADSHEET_ID' $CONFIGURATION_FILE)
        RANGE=$(jq -r '.RANGE' $CONFIGURATION_FILE)
    fi

    # Return as an associative array
    local configuration
    configuration=("${NOTION_API_KEY}" "${DATABASE_ID}" "${SPREADSHEET_ID}" "${RANGE}")
    declare -p configuration
}

# -------------------------------------------------------------------------
# Global variables
# -------------------------------------------------------------------------

# TODO: remove later on
# NOTION_API_KEY="secret_xk0qm0kDp2gaGiNG6wfZFHbOxDdVQul1bvM3sAxDCHQ"
# DATABASE_ID="24a1af3d1ebf4c9492db1221eb488fa4"
# SPREADSHEET_ID="1E2098Sr5aXUQSmQfA9vCpsl2PiEESWyVODGEj2bUKno"
# RANGE="Sheet1!A1" # Change this according to your needs

eval "$(get_or_prompt_for_configuration)"
NOTION_API_KEY=${configuration[0]}
DATABASE_ID=${configuration[1]}
SPREADSHEET_ID=${configuration[2]}
RANGE=${configuration[3]}
FILTER_FIELD="$1"
FILTER_VALUE="$2"

# -------------------------------------------------------------------------
# Execution of functions
# -------------------------------------------------------------------------
notion_data=$(get_all_notion_entries "$NOTION_API_KEY" "$DATABASE_ID" "$FILTER_FIELD" "$FILTER_VALUE")
data=$(transform_notion_data_to_sheet_data "$notion_data")

set_credentials
update_google_sheet "${SPREADSHEET_ID}" "${RANGE}" "${data}"
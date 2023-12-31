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

create_notion_query_filter() {
    local filter_field="$1"
    local filter_type="$2"
    local filter_value="$3"

    if [[ -z "$filter_field" || -z "$filter_type" || -z "$filter_value" ]]; then
        # If any of the required parameters is empty, return an empty string
        echo 'WARNING: Could not calculate filter!' 2>&1
        echo ''
    else
        # Create the filter JSON
        local filter_json=$(cat <<EOF
        {
            "property": "$filter_field",
            "$filter_type": {
                "contains": "$filter_value"
            }
        }
EOF
)
        # Return the filter JSON
        echo "$filter_json"
    fi
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
            -d "{
                \"filter\": {
                    \"or\": [
                        $(create_notion_query_filter "$filter_field" "rich_text" "$filter_value")
                    ]
                    
                }
            }" | jq
    fi
}

escape_quotes() {
    echo $1 | sed 's/"/\\"/g'
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

    echo "$range"

    payload=$(jq -n \
                    --arg range "$range" \
                    --argjson data "$data" \
                    '{
                        "range": $range,
                        "majorDimension": "ROWS",
                        "values": $data
                    }')

    echo "$payload"

    curl -X PUT \
    "https://sheets.googleapis.com/v4/spreadsheets/${spreadsheet_id}/values/${range}?valueInputOption=USER_ENTERED" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "$payload"
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

get_or_prompt_for_configuration() {
    CONFIGURATION_FILE=$(get_configuration_path)

    if [ ! -f "$CONFIGURATION_FILE" ]; then
        read -p "Enter your Notion API Key: " NOTION_API_KEY
        read -p "Enter your Database ID: " DATABASE_ID
        read -p "Enter your Spreadsheet ID: " SPREADSHEET_ID
        read -p "Enter the Google sheets cell name, where the data shall be inserted from (e.g. A1): " CELL_NAME
        read -p "Enter the Google sheets sheet name, where values shall be inserted (e.g. Sheet1): " SHEET_NAME

        # Create secrets.json
        echo "Creating configuration file '${CONFIGURATION_FILE}'" >&2
        cat <<EOF >$CONFIGURATION_FILE
{
    "NOTION_API_KEY": "$NOTION_API_KEY",
    "DATABASE_ID": "$DATABASE_ID",
    "SPREADSHEET_ID": "$SPREADSHEET_ID",
    "CELL_NAME": "$CELL_NAME",
    "SHEET_NAME": "$SHEET_NAME"
}
EOF
    else
        echo "Configuration file '${CONFIGURATION_FILE}' was found" >&2
        echo "Extracting information ..." >&2

        # Extract values from secrets.json
        NOTION_API_KEY=$(jq -r '.NOTION_API_KEY' $CONFIGURATION_FILE)
        DATABASE_ID=$(jq -r '.DATABASE_ID' $CONFIGURATION_FILE)
        SPREADSHEET_ID=$(jq -r '.SPREADSHEET_ID' $CONFIGURATION_FILE)
        CELL_NAME=$(jq -r '.CELL_NAME' $CONFIGURATION_FILE)
        SHEET_NAME=$(jq -r '.SHEET_NAME' $CONFIGURATION_FILE)
    fi

    # Return as an associative array
    local configuration
    configuration=("${NOTION_API_KEY}" "${DATABASE_ID}" "${SPREADSHEET_ID}" "${CELL_NAME}" "$SHEET_NAME")
    declare -p configuration
}

transform_value_to_value_of_interest() {
    value=$1
    jq_cmd=""
    flag=""

    if [[ $value == *"\"formula\":"* ]]; then
        formula_type=$(jq -r 'if .formula.number then "number" else "string" end' <<<"$value")
        jq_cmd=".formula.${formula_type}"
    elif [[ $value == *"\"select\":"* ]]; then
        jq_cmd=".select.name"
    elif [[ $value == *"\"url\":"* ]]; then
        jq_cmd=".url"
    elif [[ $value == *"\"checkbox\":"* ]]; then
        jq_cmd=".checkbox"
    elif [[ $value == *"\"number\":"* ]]; then
        jq_cmd=".number"
    elif [[ $value == *"\"rich_text\":"* ]]; then
        jq_cmd=".rich_text[0].plain_text"
        flag="-r"
    elif [[ $value == *"\"status\":"* ]]; then
        jq_cmd=".status.name"
        flag="-r"
    elif [[ $value == *"\"title\":"* ]]; then
        jq_cmd=".title[0].plain_text"
        flag="-r"
    elif [[ $value == *"\"relation\":"* ]]; then
        jq_cmd='[.relation[]?.id // empty] | join(", ")'
        flag="-r"
    elif [[ $value == *"\"date\":"* ]]; then
        jq_cmd=".date"
        flag="-r"
    elif [[ $value == *"\"people\":"* ]]; then
        jq_cmd='[.people[]?.id // empty] | join(", ")'
        flag="-r"
    elif [[ $value == *"\"rollup\":"* ]]; then
        jq_cmd=".rollup"
        flag="-r"
    elif [[ $value == *"\"last_edited_time\":"* ]]; then
        jq_cmd=".rollup"
        flag="-r"
    elif [[ $value == *"\"last_edited_by\":"* ]]; then
        jq_cmd=".last_edited_by.id"
        flag="-r"
    fi

    [[ $jq_cmd ]] && jq $flag "$jq_cmd" <<<"$value"
}


advanced_transform_notion_data_to_sheet_data() {

    notion_data="$1"
    results=$(echo "$notion_data" | jq '.results')

    # Iterate over each returned Notion page
    len=$(echo "$notion_data" | jq '.results | length')

    # Save the current IFS value and set IFS to newline only
    old_IFS=$IFS
    IFS=$'\n'

    # The array which will be returned at the end
    declare -a final_data=()

    echo "Formatting $len Notion entries ..." >&2

    for (( i=0; i<$len; i++ ))
    do
        # Extract each object from the array
        page=$(echo "$notion_data" | jq -r ".results[$i]")
        properties=$(echo "$page" | jq -r '.properties | to_entries[] | "\(.key): \(.value)"')

        key_row=()
        row=()
        
        for property in $properties; do

            # Restore the original IFS value after using it in for loop
            IFS=$old_IFS

            key="${property%%:*}"
            value="${property#*:}"

            # First row shall be the key row
            if [ $i -eq 0 ]; then
                key_row+=("\"$key\",")
            fi

            value_of_interest="$(transform_value_to_value_of_interest "$value")"

            # Add quotes if they dont exist yet
            if [[ "${value_of_interest:0:1}" != "\"" || "${value_of_interest: -1}" != "\"" ]]; then
              value_of_interest="\"${value_of_interest}\""
            fi

            row+=("$value_of_interest,")

            # Set IFS back to newline for the next iteration of the loop
            IFS=$'\n'
        done

        # First row shall be the key row
        if [ $i -eq 0 ]; then
            key_row_content="${key_row[*]}"
            new_key_row=$(echo "[${key_row_content%?}]" | tr -d '\n')
            final_data+=("${new_key_row},")
        fi

        # Remove final comma, which is not required
        new_row_content="${row[*]}"
        new_row=$(echo "[${new_row_content%?}]" | tr -d '\n')

        final_data+=("${new_row},")
        echo "Formatted entry $i ..." >&2

    done

    # Remove final comma, which is not required
    final_data_content="${final_data[*]}"
    echo "[${final_data_content%?}]"
}

# -------------------------------------------------------------------------
# Global variables
# -------------------------------------------------------------------------
eval "$(get_or_prompt_for_configuration)"
NOTION_API_KEY=${configuration[0]}
DATABASE_ID=${configuration[1]}
SPREADSHEET_ID=${configuration[2]}
CELL_NAME=${configuration[3]}
SHEET_NAME=${configuration[4]}
RANGE="$SHEET_NAME!$CELL_NAME"
FILTER_FIELD="$1"
FILTER_VALUE="$2"

# Overwrite Spreadsheet, if third paramter is given
if [ -n "$3" ]; then
    RANGE="$3!$CELL_NAME"
fi

# -------------------------------------------------------------------------
# Execution of functions
# -------------------------------------------------------------------------
set_credentials

notion_data=$(get_all_notion_entries "$NOTION_API_KEY" "$DATABASE_ID" "$FILTER_FIELD" "$FILTER_VALUE")

# extract results
data=$(advanced_transform_notion_data_to_sheet_data "$notion_data")

update_google_sheet "${SPREADSHEET_ID}" "${RANGE}" "${data}"
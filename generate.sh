#!/bin/bash

# GitHub repository in "owner/repo" format
REPO="SnapDBApp/app"
TMP_FOLDER="tmp"
OUTPUT_APPCAST_FILE="docs/appcast.xml"
GITHUB_API="https://api.github.com"
SIGN_UPDATE_BINARY="./bin/sign_update"
SECRET_KEY="$PRIVATE_KEY_SECRET"

# Ensure the temp folder exists
mkdir -p "$TMP_FOLDER"

# Fetch repository releases
RELEASES=$(curl -s "${GITHUB_API}/repos/${REPO}/releases" --header "Authorization: Bearer ${GITHUB_TOKEN}" --header "X-GitHub-Api-Version: 2022-11-28")

# Exit if no releases are found
if [[ -z "$RELEASES" || "$RELEASES" == "[]" ]]; then
  echo "Error: No releases found for $REPO"
  exit 1
fi

# Regenerate the appcast.xml file
rm -f "$OUTPUT_APPCAST_FILE"
touch $OUTPUT_APPCAST_FILE

# Start writing appcast.xml
cat <<EOF > "$OUTPUT_APPCAST_FILE"
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
<channel>
<title>SnapDB Releases</title>
<link>https://github.com/$REPO</link>
<description>Most recent changes with links to updates.</description>
<language>en</language>
EOF

# Process each release
echo "$RELEASES" | jq -c '.[]' | while read -r release; do
  TAG=$(echo "$release" | jq -r '.tag_name')
  PUB_DATE=$(echo "$release" | jq -r '.published_at')
  RELEASE_TITLE=$(echo "$release" | jq -r '.name')
  RELEASE_URL=$(echo "$release" | jq -r '.html_url')
  ASSET=$(echo "$release" | jq -c '.assets[] | select(.name == "SnapDB.zip")')

  if [ -n "$ASSET" ]; then
    ASSET_URL=$(echo "$ASSET" | jq -r '.browser_download_url')
    ASSET_SIZE=$(echo "$ASSET" | jq -r '.size')

    # Download and sign the asset
    ASSET_FILE="$TMP_FOLDER/$TAG.zip"
    curl -L -o "$ASSET_FILE" "$ASSET_URL"

    SIGNATURE=$(echo "$SECRET_KEY" | $SIGN_UPDATE_BINARY --ed-key-file - "$ASSET_FILE")
    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to generate signature for $ASSET_FILE"
      echo $SIGNATURE
      exit 1
    fi

    # Add release details to appcast.xml
    cat <<EOF >> "$OUTPUT_APPCAST_FILE"
<item>
<title>$RELEASE_TITLE</title>
<link>https://github.com/$REPO</link>
<sparkle:version>$TAG</sparkle:version>
<description>
<![CDATA[
Check out the <a href="$RELEASE_URL">changelog on GitHub</a> for details about this release.
]]>
</description>
<pubDate>$PUB_DATE</pubDate>
<enclosure url="$ASSET_URL"
type="application/octet-stream"
$SIGNATURE
/>
</item>
EOF
  else
    echo "No valid asset found for release $TAG"
  fi

done

# Finalize appcast.xml
cat <<EOF >> "$OUTPUT_APPCAST_FILE"
</channel>
</rss>
EOF

echo "$OUTPUT_APPCAST_FILE has been created."

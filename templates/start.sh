#!/bin/bash

set -eou pipefail

get_prop() {
    awk -v prop=$1 -F '[:,]' '$1~("\""prop"\"") {gsub(/[ \t"]/, "", $2); print $2}' 'ServerWrapperConfig.json'
}

minJavaVersion=$(get_prop "minJavaVersion")
recommendJavaVersion=$(get_prop "recommendJavaVersion")
maxJavaVersion=$(get_prop "maxJavaVersion")

# Check if update-alternatives is available
if command -v update-alternatives &>/dev/null; then
    java_command="update-alternatives --list java"
elif command -v java &>/dev/null; then
    java_command="which java"
else
    echo "Error: Java not found"
    exit 1
fi

best_version=
corresponding_jvm_path=

while read -r jvm_path; do
    version=$("$jvm_path" -version 2>&1 | head -n1 | cut -d ' ' -f 3 | cut -d '.' -f 1 | sed 's/^"\(.*\)/\1/')

    if [[ $version -eq 1 ]]; then
        version=8
    fi

    echo "Found Java $version at $jvm_path"
    
    if [[ $version -ge $minJavaVersion ]] && [[ $version -le $maxJavaVersion ]]; then
        if [[ $version -eq $recommendJavaVersion ]]; then
            best_version=$version
            corresponding_jvm_path="$jvm_path" # Save corresponding JVM path
            break
        elif [[ -z $best_version ]] || [[ $version -lt $best_version ]]; then
            best_version=$version
            corresponding_jvm_path="$jvm_path" # Save corresponding JVM path
        fi
    fi
done < <($java_command 2>/dev/null)

if [[ -z "$best_version" ]]; then
    echo "Error: No suitable Java version found"
    exit 1
fi

echo "Selected $best_version at $corresponding_jvm_path"

"$corresponding_jvm_path" @jvm_args.txt -cp "ServerWrapper.jar" "pro.gravit.launcher.server.ServerWrapper"
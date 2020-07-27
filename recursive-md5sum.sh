#!/usr/bin/env bash
################################################################################
#                                                                              #
# Toazd 2020 Unlicense                                                         #
# Read the file UNLICENSE or refer to <https://unlicense.org> for more details #
# Designed to work on bash versions as low as 3.2                              #
#   without using gnu coreutils                                                #
#                                                                              #
# Purpose:                                                                     #
#   Given a search path (required), a save path (optional), and a file         #
#   extension (optional) locate all files in the search path and run md5sum    #
#   on each one and save the results to a single file.                         #
#                                                                              #
#   Optional parameters preceding explicitly defined parameters are required.  #
#   For example, if you want to explicitly define the file extension search    #
#   pattern, then the save path optional parameter must also be explicitly     #
#   defined.                                                                   #
#                                                                              #
#   If the minimum amount of parameters is supplied then defaults are assumed  #
#   for the remaining optional parameters.                                     #
#    ./script.sh /home                                                         #
#   is the same as explicitly typing                                           #
#    ./script.sh /home "**"                                                    #
#                                                                              #
#    When the file extension parameter is not supplied or it is explicitly     #
#    defined as "**" then all files will be located instead of by the pattern  #
#    *.file_extension.                                                         #
#                                                                              #
################################################################################

# Shell options
shopt -qs extglob


# Initialize global variables
sSEARCH_PATH=${1-}
sSAVE_PATH=${2:-$PWD}
sFILE_EXT=${3:-"**"}
sSAVE_FILE=""
sWORK_PATH=$PWD # in case $OLDPWD isn't supported or set correctly
iaFILES=()
iSTART_SECONDS=0
iEND_SECONDS=0
iCOUNTER=0
iTOTAL_FILES=0
iPROGRESS=0
iPREV_PROGRESS=1

# Basic usage
ShowUsage() {
    printf "\nUsage:\n\t%s\n\n\t%s\n\n" "$0 [search_path] [save_path] [file_extension]" "file_extension \"**\" = all files (instead of *.file_extension)"
    exit
}

# Format time in seconds to a more human friendly format
FormatTimeDiff() {
    local iSECONDS=$(( iEND_SECONDS - iSTART_SECONDS ))
    local sRESULT=""

    [[ $iSECONDS -lt 1 ]] && { sRESULT="<1 second"; printf "%s" "$sRESULT"; return 0; }
    [[ $iSECONDS -eq 1 ]] && { sRESULT="1 second"; printf "%s" "$sRESULT"; return 0; }
    [[ $iSECONDS -gt 1 && $iSECONDS -lt 60 ]] && { sRESULT="$iSECONDS seconds"; printf "%s" "$sRESULT"; return 0; }
    [[ $iSECONDS -ge 60 && $iSECONDS -lt 120 ]] && { sRESULT="$iSECONDS seconds (1 minute)"; printf "%s" "$sRESULT"; return 0; }
    [[ $iSECONDS -ge 120 ]] && { sRESULT="$iSECONDS seconds ($(( iSECONDS / 60 )) minutes, $(( iSECONDS % 60 )) seconds)"; printf "%s" "$sRESULT"; return 0; }

    return 0
}

# Basic parameter checks
[[ $sSEARCH_PATH = @(""|"-h"|"-H"|"-help"|"--help") ]] && ShowUsage

# If files are supplied when paths are expected
[[ -f $sSAVE_PATH || -f $sSEARCH_PATH ]] && ShowUsage

# Get the full path to search path and save path
# supports relative paths during invocation
if cd "$sSEARCH_PATH"; then
    sSEARCH_PATH=$PWD
    if cd "$sWORK_PATH"; then
        if cd "$sSAVE_PATH"; then
            sSAVE_PATH=$PWD
            if ! cd "$sWORK_PATH"; then
                echo "Error returning to script work path: $sWORK_PATH"
                exit 1
            fi
        else
            echo "Error changing to save path: $sSAVE_PATH"
            exit 1
        fi
    else
        echo "Error returning to script work path: $sWORK_PATH"
        exit 1
    fi
else
    echo "Error changing to search path: $sSEARCH_PATH"
    exit 1
fi

# Check for write permission to the save path
# This will also fail if the save path does not exist
[[ -w $sSAVE_PATH ]] || { echo "No write access to save path or save path does not exist: \"$sSAVE_PATH\""; exit; }

# Find all files in the search path and assign the results to an indexed array after sorting them
# Each method is timed in whole seconds
# iaFILES is not required but is used for clarity (if no array is supplied MAPFILE is used)
# Find all specified files in the search path and based on the pattern provided then assign the results to an indexed array after sorting them
# Each method is timed in whole seconds
iCOUNTER=0
if [[ $sFILE_EXT = "**" ]]; then
    printf "%s\033[s" "Searching \"$sSEARCH_PATH\" for all files"
    iSTART_SECONDS="$(date +%s)"
    while IFS= read -r; do
        iaFILES+=("$REPLY")
        iCOUNTER=$(( iCOUNTER +1 ))
        printf "\033[u%s" "...$iCOUNTER"
    done < <(find "${sSEARCH_PATH}/" -type f -iwholename "*" 2>/dev/null | LC_ALL=C sort -u)
    iEND_SECONDS="$(date +%s)"
    printf "\033[u\033[0K\n"
else
    iSTART_SECONDS="$(date +%s)"
    while IFS= read -r; do
        iaFILES+=("$REPLY")
        iCOUNTER=$(( iCOUNTER +1 ))
        printf "\033[u%s" "...$iCOUNTER"
    done < <(find "${sSEARCH_PATH}/" -type f -iwholename "*.${sFILE_EXT}" 2>/dev/null | LC_ALL=C sort -u)
    iEND_SECONDS="$(date +%s)"
    printf "\033[u\033[0K\n"
fi

# Report how many files were found and roughly how long it took to find and sort them
# NOTE Find returns a newline if nothing is found
# If the array has length 0 then it hasn't been modified from initialization
# (shouldn't happen but if set -e is removed or disabled and find fails somehow, it can happen)
if [[ ${#iaFILES[@]} -le 1 ]]; then
    echo "No files found matching that search pattern"
    exit
elif [[ ${#iaFILES[@]} -gt 1 ]]; then
    echo "${#iaFILES[@]} files found and sorted in $(FormatTimeDiff)"
    # Set the total files variable used for progress output
    # NOTE A seperate value is not required but may cost less computationally
    iTOTAL_FILES=${#iaFILES[@]}
else
    # Unknown error
    echo "Unknown error detecting number of files found"
    exit 1
fi

# Create the output file name and path
# Using all the parent folders for the name
# and replacing / with -
# eg. "/home/toazd/github" becomes "save_path/home-toazd-github.md5"
# TODO better save file naming scheme

# Start with the full path of the search path
sSAVE_FILE=$sSEARCH_PATH
# Replace / with -
sSAVE_FILE="${sSAVE_FILE//\//-}"
# Remove a leading dash "-" if it exists
[[ ${sSAVE_FILE:0:1} = "-" ]] && sSAVE_FILE="${sSAVE_FILE:1:${#sSAVE_FILE}}"
# Prefix the file name with the path
sSAVE_FILE="${sSAVE_PATH}/${sSAVE_FILE}.md5"

# Report the name of the output file
echo "Output file: $sSAVE_FILE"

# If a save file already exists where we want to write to, back it up by renaming
# it with a (hopefully) unique suffix of date +%s (seconds since 1970-01-01 00:00:00 UTC)
[[ -f $sSAVE_FILE ]] && { echo "Existing output file detected..."; mv -fv "$sSAVE_FILE" "${sSAVE_FILE%.*}_$(date +%s).bak"; }

# Process each file defined as an element in the iaFILES array
printf "%s\033[s" "Processing files with md5sum..."
iSTART_SECONDS="$(date +%s)"
for (( iCOUNTER=0; iCOUNTER<${#iaFILES[@]}; iCOUNTER++ )); do

    # Run md5sum on the current file in the array and redirect the output to the save file
    [[ -e ${iaFILES[iCOUNTER]} && -r ${iaFILES[iCOUNTER]} ]] && md5sum "${iaFILES[iCOUNTER]}" >> "$sSAVE_FILE"

    # Calculate the progress in whole-number % using no external commands
    # NOTE Calling external commands (like bc) during the main loop is too costly for long operations
    iPROGRESS=$(( (iCOUNTER*100) / iTOTAL_FILES ))

    # Report the progress in whole-number % using carriage return to overwrite
    # the same line on subsequent updates. Only output if the current progress
    # is not equal to the previous progress.
    # This prevents the same progress from being written multiple times
    # NOTE iPROGRESS and iPREV_PROGRESS must not be equal at initialization
    #      so that 0% is initially displayed for progress <1%
    [[ $iPROGRESS -ne $iPREV_PROGRESS ]] && printf "\033[u%s" "${iPROGRESS}%"

    # Update the previous progress variable
    # This variable is required so we don't needlessly update the screen with the same %
    iPREV_PROGRESS=$iPROGRESS
done
iEND_SECONDS="$(date +%s)"

# Report how many files were processed and how long it took in whole seconds
printf "\r\033[0K%s\n%s\n" "$iCOUNTER files processed in $(FormatTimeDiff)"

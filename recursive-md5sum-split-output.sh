#!/usr/bin/env bash
################################################################################
#                                                                              #
# Toazd 2020 Unlicense                                                         #
# Read the file UNLICENSE or refer to <https://unlicense.org> for more details #
#                                                                              #
# Purpose:                                                                     #
#   Given a search path (required), a save path (optional), a file extension   #
#   (optional), and a tag (optional) locate all files in the search path and   #
#   run md5sum on each one and save the results into seperate files.           #
#                                                                              #
#   Optional parameters preceding explicitly defined parameters are required.  #
#   For example, if you want to explicitly define the tag, then the save path  #
#   and file extension search pattern optional parameters must also be         #
#   explicitly defined.                                                        #
#                                                                              #
#   If the minimum amount of parameters is supplied then defaults are assumed  #
#   for the remaining optional parameters.                                     #
#    ./script.sh /home                                                         #
#   is the same as explicitly typing                                           #
#    ./script.sh /home "**" ""                                                 #
#                                                                              #
#   When the file extension parameter is not supplied or it is explicitly      #
#   defined as "**" then all files will be located instead of by the pattern   #
#   *.file_extension.                                                          #
#                                                                              #
################################################################################

# Shell options
shopt -qs extglob

# Attempt to set bash compatibility mode to < 4.0
# shopt compat31
#   If set, Bash changes its behavior to that of version 3.1 with respect to quoted arguments to the conditional
#   command’s ‘=~’ operator and with respect to locale-specific string comparison when using the [[ conditional
#   command’s ‘<’ and ‘>’ operators. Bash versions prior to bash-4.1 use ASCII collation and strcmp(3); bash-4.1
#   and later use the current locale’s collation sequence and strcoll(3).
# shopt compat32
#   If set, Bash changes its behavior to that of version 3.2 with respect to locale-specific string comparison
#   when using the [[ conditional command’s ‘<’ and ‘>’ operators (see previous item) and the effect of interrupting
#   a command list. Bash versions 3.2 and earlier continue with the next command in the list after one terminates due to an interrupt.
if ! shopt -qs compat32; then
    shopt -qs compat31
fi

# -e  Exit immediately if a command exits with a non-zero status.
# -E  If set, the ERR trap is inherited by shell functions.
# -u  Treat unset variables as an error when substituting.
set -eEu

# Initialize global variables
sSEARCH_PATH="${1-}"
sSAVE_PATH="${2:-"$(pwd -P)"}"
sFILE_EXT="${3:-"**"}"
sTAG="${4:-""}"
sBASENAME_PATH=""
sSAVE_FILE=""
sSAVE_PATH_PARENT=""
iaFILES=()
iSTART_SECONDS=0
iEND_SECONDS=0
iCOUNTER=0
iTOTAL_FILES=0
iPROGRESS=0
iPREV_PROGRESS=1

# Basic usage
ShowUsage() {
    printf "Usage:\n\t%s\n\n\t%s\n\t%s\n\t%s\n\t%s\n\t%s\n" \
           "$0 [search_path] [save_path] [file_extension] [tag]" \
           "Only the first parameter is required. Set file_extension to \"**\" to search all files." \
           "Given one parameter in the current path the remaining defaults would be assumed:" \
           "save_path=\"$sSAVE_PATH\"" \
           "file_extension=\"$sFILE_EXT\"" \
           "tag=\"$sTAG\""
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
[[  $# -lt 1 || $sSEARCH_PATH = @(""|"-h"|"-H"|"-help"|"--help") ]] && ShowUsage

# If files are supplied when paths are expected
[[ -f $sSAVE_PATH || -f $sSEARCH_PATH ]] && ShowUsage

# Get the full, real path of the search path
sSAVE_PATH="$(realpath -q "$sSAVE_PATH")"

# Check for write permission to the save path
# This will also fail if the save path does not exist
[[ -w $sSAVE_PATH ]] || { echo "No write access to save path or save path does not exist: \"$sSAVE_PATH\""; exit; }

# Find all files in the search path and assign the results to an indexed array after sorting them
# Each method is timed in whole seconds
# iaFILES is not required but is used for clarity (if no array is supplied MAPFILE is used)
echo "Search path: $sSEARCH_PATH"
if [[ $sFILE_EXT = "**" ]]; then
    iSTART_SECONDS="$(date +%s)"
    mapfile -t <<< "$(find "$sSEARCH_PATH" -type f -iwholename "*" | LC_ALL=C sort -u)" iaFILES
    iEND_SECONDS="$(date +%s)"
else
    iSTART_SECONDS="$(date +%s)"
    mapfile -t <<< "$(find "$sSEARCH_PATH" -type f -iwholename "*.${sFILE_EXT}" | LC_ALL=C sort -u)" iaFILES
    iEND_SECONDS="$(date +%s)"
fi

# Report how many files were found and roughly how long it took to find and sort them
# NOTE Find returns a newline if nothing is found (no files = length 1 for the array)
# If the array has length 0 then it hasn't been modified from initialization
# (shouldn't happen but if set -e is removed or disabled and find fails somehow, it can happen)
if [[ ${#iaFILES[@]} -le 1 ]]; then
    echo "No files found"
    exit 1
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

# Process each file defined as an element in the iaFILES array
printf "%s\033[s" "Processing files with md5sum..."
iSTART_SECONDS="$(date +%s)"
for (( iCOUNTER=0; iCOUNTER<${#iaFILES[@]}; iCOUNTER++ )); do

    # Get the basename of the parent folder of the file
    sBASENAME_PATH="${iaFILES[iCOUNTER]%/*}"
    sBASENAME_PATH="${sBASENAME_PATH##*/}"

    # Get the basename of the parent of the folder the file is in
    sSAVE_PATH_PARENT="${iaFILES[iCOUNTER]%/*}"
    sSAVE_PATH_PARENT="${sSAVE_PATH_PARENT%/*}"
    sSAVE_PATH_PARENT="${sSAVE_PATH_PARENT##*/}"

    # Concatenate the save path, save path parent, basename path,
    # and the optional tag to form the full path and file name to output to
    if [[ -z $sTAG ]]; then
        # If no tag parameter is explicitly defined or it is set to NULL
        sSAVE_FILE="${sSAVE_PATH}/${sSAVE_PATH_PARENT}_${sBASENAME_PATH}.md5"
    elif [[ -n $sTAG ]]; then
        # If a tag parameter is explicitly defined, prefix the tag with an underscore "_"
        sSAVE_FILE="${sSAVE_PATH}/${sSAVE_PATH_PARENT}_${sBASENAME_PATH}_${sTAG}.md5"
    fi

    # Run md5sum on the current file in the array and redirect the output to the save file
    md5sum "${iaFILES[iCOUNTER]}" >> "$sSAVE_FILE"

    # Calculate the progress in whole-number % using no external commands
    # NOTE Calling external commands (like bc) during the main loop is too costly for long operations
    iPROGRESS=$(( (iCOUNTER*100) / iTOTAL_FILES ))

    # Report the progress in whole-number % using carriage return to overwrite
    # the same line on subsequent updates. Only output if the current progress
    # is not equal to the previous progress.
    # This prevents the same progress from being written multiple times
    # NOTE iPROGRESS and iPREV_PROGRESS must not be equal at initialization
    #      so that 0% is initially displayed for progress <1%
    [[ $iPROGRESS -ne $iPREV_PROGRESS ]] && printf "%s\033[u" "${iPROGRESS}% complete"

    # Update the previous progress variable
    # This variable is required so we don't needlessly update the screen with the same %
    iPREV_PROGRESS=$iPROGRESS
done
iEND_SECONDS="$(date +%s)"

# Report how many files were processed and how long it took in whole seconds
printf "\033[2K\r%s\n" "$iCOUNTER files processed in $(FormatTimeDiff)"

#!/usr/bin/env bash
################################################################################
#                                                                              #
# Toazd 2020 Unlicense                                                         #
# Read the file UNLICENSE or refer to <https://unlicense.org> for more details #
# Designed to work on bash versions as low as 3.2                              #
#                                                                              #
# NOTE:                                                                        #
#   This version is customized specifically for the requirements discussed in  #
#   the following reddit thread:                                               #
#   /r/bash/comments/hi9wwn/macdebian_creating_bash_script_to_get_md5_values   #
#                                                                              #
# Purpose:                                                                     #
#   Given a search path (required), a save path (optional), a file extension   #
#   (optional), and a tag (optional) locate all files in the search path and   #
#   run md5sum on each one and save the results into seperate files. Each      #
#   output file name is prefixed by the entire path to the file being checked  #
#   and suffixed by an underscore "_" and then a tag if one is provided. If a  #
#   tag is not provided than the output file name will be only the path.       #
#     No tag example output file name:                                         #
#       home-toazd-github.md5                                                  #
#     Example output file name with TAG="example"                              #
#       home-toazd-github_example.md5                                          #
#                                                                              #
# Usage notes:                                                                 #
#                                                                              #
#   Both md5sum read modes are supported which is currently text and binary    #
#   To change the md5sum mode from the default (text) or add any other         #
#   parameters change them on ~line 209 (not all parameters are supported)     #
#                                                                              #
#   Optional parameters preceding explicitly defined parameters are required.  #
#   For example, if you want to explicitly define the tag, then the save path  #
#   and file extension search pattern optional parameters must also be         #
#   provided.                                                        #
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

# Initialize global variables
sSEARCH_PATH=${1-}
sSAVE_PATH=${2:-$PWD}
sFILE_EXT=${3:-"**"}
sTAG=${4-}
sSAVE_FILE=""
sFILE_PATH=""
sWORK_PATH=$PWD # in case $OLDPWD isn't supported or set correctly
sMD5_OUTPUT_LINE=""
sMD5_OUTPUT_LINE_CHECKSUM=""
sMD5_OUTPUT_LINE_FILE=""
iaFILES=()
iSTART_SECONDS=0
iEND_SECONDS=0
iCOUNTER=0
iTOTAL_FILES=0
iPROGRESS=0
iPREV_PROGRESS=1
iMD5SUM_BINARY_MODE=0

# Basic usage help
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

# Check for write permission to the save path
# This will also fail if the save path does not exist
[[ -w $sSAVE_PATH ]] || { echo "No write access to save path or save path does not exist: \"$sSAVE_PATH\""; exit 1; }

# Get the full path to search path and save path
# without using realpath, dirname, readlink, etc.
# NOTE supports relative paths at invocation
if cd "$sSEARCH_PATH"; then
    sSEARCH_PATH=$PWD
    if cd "$sWORK_PATH"; then
        if cd "$sSAVE_PATH"; then
            sSAVE_PATH=$PWD
            if ! cd "$sWORK_PATH"; then
                echo "Error returning to original work path: $sWORK_PATH"
                exit 1
            fi
        else
            echo "Error changing to save path: $sSAVE_PATH"
            exit 1
        fi
    else
        echo "Error returning to original work path: $sWORK_PATH"
        exit 1
    fi
else
    echo "Error changing to search path: $sSEARCH_PATH"
    exit 1
fi

# Find all specified files in the search path based on the pattern provided
# then assign the results to an indexed array after sorting them case-insensitive
# NOTE "printf '%(%s)T\n' -1" requires bash 4.2
# NOTE $EPOCHSECONDS / $EPOCHREALTIME requires bash 5.0
iCOUNTER=0
if [[ $sFILE_EXT = "**" ]]; then
    printf "%s\033[s" "Searching \"$sSEARCH_PATH\" for all files"
    iSTART_SECONDS=$(date +%s)
    while IFS= read -r; do
        iaFILES+=("$REPLY")
        iCOUNTER=$(( iCOUNTER +1 ))
        printf "\033[u%s" "...$iCOUNTER"
    done < <(find "${sSEARCH_PATH}/" -type f -iname "*" 2>/dev/null | LC_ALL=C sort -f)
    iEND_SECONDS=$(date +%s)
    printf "\033[u\033[0K\n"
else
    printf "%s\033[s" "Searching \"$sSEARCH_PATH\" for \"*.${sFILE_EXT}\" files"
    iSTART_SECONDS=$(date +%s)
    while IFS= read -r; do
        iaFILES+=("$REPLY")
        iCOUNTER=$(( iCOUNTER +1 ))
        printf "\033[u%s" "...$iCOUNTER"
    done < <(find "${sSEARCH_PATH}/" -type f -iname "*.${sFILE_EXT}" 2>/dev/null | LC_ALL=C sort -f)
    iEND_SECONDS=$(date +%s)
    printf "\033[u\033[0K\n"
fi

# Report how many files were found and roughly how long it took to find and sort them
# NOTE Find returns a newline if nothing is found (no files = length 1 for the array)
# If the array has length 0 then it hasn't been modified from initialization
# (shouldn't happen but if set -e is removed or disabled and find fails somehow, it can happen)
if [[ ${#iaFILES[@]} -le 1 ]]; then
    echo "No files found matching that search pattern"
    exit 0
elif [[ ${#iaFILES[@]} -gt 1 ]]; then
    echo "${#iaFILES[@]} files found and sorted in $(FormatTimeDiff)"
    # Set the total files variable used for progress output
    # NOTE A seperate value is not required but may cost less computationally
    # versus computing it for each iteration of the main loop
    iTOTAL_FILES=${#iaFILES[@]}
else
    # Unknown error
    echo "Unknown error detecting number of files found"
    exit 1
fi

# Process each file defined as an element in the iaFILES array with md5sum
# NOTE save and restore cursor position escape sequences (\033[s and \033[u) are used
# very old and non-standard terminals will not display the progress as intended
printf "%s\033[s" "Processing files with md5sum..."
iSTART_SECONDS=$(date +%s)
for (( iCOUNTER=0; iCOUNTER<${#iaFILES[@]}; iCOUNTER++ )); do

    # Use the entire file path to create the output file prefix
    sFILE_PATH=${iaFILES[iCOUNTER]}
    # Trim the file name away
    sFILE_PATH=${sFILE_PATH%/*}
    # Convert forward-slashes "/" to dashes "-"
    sFILE_PATH=${sFILE_PATH//\//-}

    # Remove leading "--" or "-"
    # NOTE If the first two characters are double dashes "--"
    # then the root path "/" was used as a search path
    if [[ ${sFILE_PATH:0:2} = "--" ]]; then
        sFILE_PATH=${sFILE_PATH:2:${#sFILE_PATH}}
    elif [[ ${sFILE_PATH:0:1} = "-" ]]; then
        sFILE_PATH=${sFILE_PATH:1:${#sFILE_PATH}}
    fi

    # Create the full path and file name for the output file
    # using the save path and the file path and including
    # a tag if one was provided
    # If no tag parameter is explicitly defined or it is set to NULL
    if [[ -z $sTAG ]]; then
        if [[ -n $sFILE_PATH ]]; then
            sSAVE_FILE="${sSAVE_PATH}/${sFILE_PATH}".md5
        else
            printf "\n%s\n%s\n%s\n%s\n" "Error transforming file path into output file prefix" "File: \"${iaFILES[iCOUNTER]}\"" "Save path: \"$sSAVE_PATH\"" "Computed prefix: \"$sFILE_PATH\""
            exit 1
        fi
    # If a tag parameter is explicitly defined, prefix the tag with an underscore "_"
    elif [[ -n $sTAG ]]; then
        if [[ -n $sFILE_PATH ]]; then
            sSAVE_FILE="${sSAVE_PATH}/${sFILE_PATH}_${sTAG}".md5
        else
            printf "\n%s\n%s\n%s\n%s\n%sn" "Error transforming file path into output file prefix" "File: \"${iaFILES[iCOUNTER]}\"" "Save path: \"$sSAVE_PATH\"" "Tag: $sTAG" "Computed prefix: \"$sFILE_PATH\""
            exit 1
        fi
    # If something went wrong with obtaining a tag, default to no TAG
    else
        if [[ -n $sFILE_PATH ]]; then
            sSAVE_FILE="${sSAVE_PATH}/${sFILE_PATH}".md5
        else
            printf "\n%s\n%s\n%s\n%s\n" "Error transforming file path into output file prefix" "File: \"${iaFILES[iCOUNTER]}\"" "Save path: \"$sSAVE_PATH\"" "Computed prefix: \"$sFILE_PATH\""
            exit 1
        fi
    fi

    # Get the output line from md5sum
    # Only process files that can be read by the current user
    # NOTE add any desired md5sum parameters here
    [[ -r ${iaFILES[iCOUNTER]} ]] && sMD5_OUTPUT_LINE=$(md5sum "${iaFILES[iCOUNTER]}")

    # Get the checksum portion of the output line
    sMD5_OUTPUT_LINE_CHECKSUM=${sMD5_OUTPUT_LINE%% *}

    # Get the full path and/or file name from the output line
    sMD5_OUTPUT_LINE_FILE=${sMD5_OUTPUT_LINE#* }

    # Determine if md5sum was ran in text or binary mode (determines the output format)
    # by checking for a leading asterisk "*" (binary mode) or space " " (text mode)
    # NOTE just like md5sum, the default is text mode
    if [[ ${sMD5_OUTPUT_LINE_FILE:0:1} = "*" ]]; then
        iMD5SUM_BINARY_MODE=1
        # Remove the leading asterisk "*"
        sMD5_OUTPUT_LINE_FILE=${sMD5_OUTPUT_LINE_FILE:2:${#sMD5_OUTPUT_LINE_FILE}}
    elif [[ ${sMD5_OUTPUT_LINE_FILE:0:1} = " " ]]; then
        iMD5SUM_BINARY_MODE=0
        # Remove the leading space " "
        sMD5_OUTPUT_LINE_FILE=${sMD5_OUTPUT_LINE_FILE:2:${#sMD5_OUTPUT_LINE_FILE}}
    else
        echo "Error checking md5sum output line file name for a mode character (asterisk \"*\" for binary mode, space \" \" for text mode)"
        echo "Output line: \"$sMD5_OUTPUT_LINE_FILE\""
    fi

    # Remove the entire path from the file name
    # NOTE if md5sum happens to run in binary mode, this also removes the leading * or space
    sMD5_OUTPUT_LINE_FILE=${sMD5_OUTPUT_LINE_FILE##*/}

    # Reformat the output line according to the mode, reusing an existing variable, using
    # the checksum and reformatted file name
    # NOTE text mode - fields seperated by a space " ", with the file having a leading space " "
    # NOTE binary mode - fields seperated by a space " ", with the file having a leading asterisk "*"
    if [[ $iMD5SUM_BINARY_MODE = "0" ]]; then
        sMD5_OUTPUT_LINE="${sMD5_OUTPUT_LINE_CHECKSUM}  ${sMD5_OUTPUT_LINE_FILE}"
    elif [[ $iMD5SUM_BINARY_MODE = "1" ]]; then
        sMD5_OUTPUT_LINE="${sMD5_OUTPUT_LINE_CHECKSUM} *${sMD5_OUTPUT_LINE_FILE}"
    fi

    # Save the output line to the save file
    printf "%s\n" "$sMD5_OUTPUT_LINE" >> "$sSAVE_FILE"

    # Calculate the progress in whole-number %
    iPROGRESS=$(( (iCOUNTER*100) / iTOTAL_FILES ))

    # Report the progress in whole-number %
    # Only output if the current progress
    # is not equal to the previous progress.
    # This prevents the same progress from being written multiple times
    # NOTE iPROGRESS and iPREV_PROGRESS must not be equal at initialization
    #      so that 0% is initially displayed for progress <1%
    [[ $iPROGRESS -ne $iPREV_PROGRESS ]] && printf "\033[u%s" "${iPROGRESS}% complete"

    # Update the previous progress variable
    # This variable is required so we don't needlessly update the screen with the same %
    iPREV_PROGRESS=$iPROGRESS
done
iEND_SECONDS=$(date +%s)

# Report how many files were processed and how long it took in whole seconds
printf "\r\033[0K%s\n" "$iCOUNTER files processed in $(FormatTimeDiff)"

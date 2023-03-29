#!/bin/sh
#
# Copyright (c) 2023 Torsten Keil - All Rights Reserved
#
# Unauthorized copying or redistribution of this file in source and binary forms via any medium
# is strictly prohibited.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#

################################################################################
#
# This is the install wrapper that allows to run an installer with one command in a remote manner ala:
#
# Sample:
#     curl https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/master/installer.sh | sh
#     or
#     wget -q -O - https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/installer.sh | sh
#
# The install wrapper download the latest installer in a temporary directory and executes it.
# This is useful to allow installers like the ones created via makeself to run their validation
# (e.g. checksum, decryption or asymmetric signature check).
#
################################################################################

{ # Prevent execution if this script was only partially downloaded


####################
# CONFIG - STATIC
####################

__INSTALLER_GITHUB_ORG_REPO_NAME=asvsam/asvsam
__INSTALLER_INSTALLER_FILENAME=Installer.run


####################
# PARAMETERS AND CONFIG DYNAMIC
####################

# Check parameter count - On Fail print usage
if test ! "$#" -eq 0 -a ! "$#" -eq 2; then
  usage
  exit 0
fi

if test "$#" -eq 4; then
    __INSTALLER_GITHUB_ORG_REPO_NAME=${1}
    __INSTALLER_INSTALLER_FILENAME=${4}
fi

__INSTALLER_GITHUB_URI=https://github.com/${__INSTALLER_GITHUB_ORG_REPO_NAME}
__INSTALLER_GITHUB_RELEASE_URI=https://api.github.com/repos/${__INSTALLER_GITHUB_ORG_REPO_NAME}/releases/latest


####################
# FUNCTIONS
####################

usage() {
  cat << __EOF__
NAME
    ${0} - installer wrapper

SYNOPSIS
    ${0}
    ${0} GITHUB_ORG_REPO_NAME INSTALLER_FILENAME

DESCRIPTION

    This is the install wrapper that allows to run an installer with one command in a remote manner.

    Sample:
    curl https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/master/${0} | sh
    or
    wget -q -O - https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/${0} | sh

    The install wrapper download the latest installer in a temporary directory and executes it. This is useful to allow installers like the ones created via makeself to run their validation (e.g. checksum, decryption or asymmetric signature check).

OPTIONS:
    GITHUB_ORG_REPO_NAME        The Github GITHUB_ORG_NAME/GITHUB_REPO_NAME
    INSTALLER_FILENAME          The filename off the released installer file (Shell script) on GitHub.
__EOF__
}

stop_it() {
    echo "$0 - ERROR: " "$@" >&2
    exit 1
}

cleanup() {
    rm -rf "$tmpDir"
}


####################
# PREPARE
####################

# Are we running on a terminal?
if [ ! -t 1 ]; then
  INTERACTIVE=0
else
  INTERACTIVE=1
fi

# Set default UMASK
umask 0022

# Set trap to cleanup
trap cleanup EXIT INT QUIT TERM


####################
# MAIN LOGIC
####################

# Create temp dir
tmpDir="$(mktemp -d -t asvsam-installer.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX \
    || stop_it "Can't create temporary directory for downloading ASV-SAM-Installer")"

# Git latest release of installer file
URL=$(curl -s ${__INSTALLER_GITHUB_RELEASE_URI} \
    | grep "browser_download_url.*${__INSTALLER_INSTALLER_FILENAME}" \
    | cut -d : -f 2,3 \
    | tr -d \")
if "${URL}" = ""; then
    stop_it "Could not create URL for latest installer version.
This usually means the config provided to the INSTALL_WRAPPER is not correct (e.g. __INSTALLER_GITHUB_ORG_REPO_NAME, __INSTALLER_GITHUB_RELEASE_URI or __INSTALLER_INSTALLER_FILENAME).
Please refer to if: ${__INSTALLER_GITHUB_URI}"
fi

# Get installer - Download in temp directory
curl --fail -L ${URL} -o "$tmpDir/${__INSTALLER_INSTALLER_FILENAME}" \
    || stop_it "Could not load latest installer version from ${URL}. Please refer to: ${__INSTALLER_GITHUB_URI}"

# Run installer
$tmpDir/Installer.run

# Cleanup - But should also happen via trap, but better is better
rm -rf $tmpDir

} # End of wrapping

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
#     curl -L https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/master/installer.sh | sh
#     or
#     curl -L https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/master/installer.sh | sh -s -- --github-repo-name GITHUB_ORG_REPO_NAME --installer-filename FILENAME
#     or
#     wget -q -O - https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/installer.sh | sh
#
# The install wrapper download the latest installer in a temporary directory and executes it.
# This is useful to allow installers like the ones created via makeself to run their validation
# (e.g. checksum, decryption or asymmetric signature check).
#
################################################################################

{ # Prevent execution if this script was only partially downloaded

# Abort on nonzero exitstatus
set -o errexit
# Abort on unbound variable
set -o nounset
# Don't hide errors within pipes
#set -o pipefail


####################
# CONFIG - STATIC
####################

# Project name. Used for instance: /etc/<project_name>, /tmp/<project_name>-installer.XXX...
__INSTALLER_PROJECT_NAME=asvsam
__INSTALLER_GITHUB_ORG_REPO_NAME=asvsam/asvsam
__INSTALLER_INSTALLER_FILENAME=Install.run
__INSTALLER_APP_PUBLIC_TRUSTED_KEYRING_FILENAME=trusted.gpg


####################
# PARAMETERS AND CONFIG DYNAMIC
####################

# Default values
__INSTALLER_SKIP_SIGNATURE_VALIDATION=false

# Check parameters - On Fail print usage
while test $# -gt 0; do
  case "${1}" in
    -r|--github-repo-name)
        shift;
        __INSTALLER_GITHUB_ORG_REPO_NAME="${1}"
        ;;
    -i|--installer-filename)
        shift;
        __INSTALLER_INSTALLER_FILENAME="${1}"
        ;;
    -s|--skip-signature-validation)
        __INSTALLER_SKIP_SIGNATURE_VALIDATION=true
        ;;
    -h|--help|*)
        usage
        exit 0
        ;;
  esac
  shift
done

# Calculated values
__INSTALLER_GITHUB_URI=https://github.com/${__INSTALLER_GITHUB_ORG_REPO_NAME}
__INSTALLER_GITHUB_RELEASE_URI=https://api.github.com/repos/${__INSTALLER_GITHUB_ORG_REPO_NAME}/releases/latest

# Installer gpg signature file name
__INSTALLER_INSTALLER_SIG_FILENAME=${__INSTALLER_INSTALLER_FILENAME}.sig

__INSTALLER_APP_ETC=/etc/${__INSTALLER_PROJECT_NAME}
# Public KeyRing: trusted.gpg
__INSTALLER_APP_PUBLIC_TRUSTED_KEYRING=${__INSTALLER_APP_ETC}/${__INSTALLER_APP_PUBLIC_TRUSTED_KEYRING_FILENAME}


####################
# FUNCTIONS
####################

usage() {
  cat << __EOF__
NAME
    ${0} - installer wrapper

SYNOPSIS
    ${0}
    ${0} --github-repo-name GITHUB_ORG_REPO_NAME --installer-filename INSTALLER_FILENAME

DESCRIPTION

    This is the install wrapper that allows to run an installer with one command in a remote manner.

    Sample:
    curl -L https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/master/${0} | sh
    or
    curl -L https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/master/${0} | sh -s -- --github-repo-name GITHUB_ORG_REPO_NAME --installer-filename FILENAME
    or
    wget -q -O - https://raw.githubusercontent.com/GITHUB_ORG_NAME/GITHUB_REPO_NAME/${0} | sh

    The install wrapper download the latest installer in a temporary directory and executes it. This is useful to allow installers like the ones created via makeself to run their validation (e.g. checksum, decryption or asymmetric signature check).

OPTIONS:
    -r, --github-repo-name GITHUB_ORG_REPO_NAME     The Github GITHUB_ORG_NAME/GITHUB_REPO_NAME
    -i, --installer-filename FILENAME               The filename off the released installer file (Shell script) on GitHub.
    -s, --skip-signature-validation                 Skip the gpg signature validation - !!! Potentially dangerous !!!
__EOF__
}

stop_it() {
    echo "$0 - ERROR: " "$@" >&2
    exit 1
}

cleanup() {
    rm -rf "${tmpDir}"
}

show_public_keyring() {
    gpg --no-default-keyring --keyring gnupg-ring:${__INSTALLER_APP_PUBLIC_TRUSTED_KEYRING} --list-keys --keyid-format long
}

validate_installer_signature() {
    INSTALLER_PATH=$1

    (gpg --no-default-keyring --keyring gnupg-ring:${__INSTALLER_APP_PUBLIC_TRUSTED_KEYRING} --verify ${INSTALLER_PATH}.sig ${INSTALLER_PATH}) \
        && true \
        || false
}

check_installation_status() {

    # Check prerequisites
    IS_CURL_INSTALLED=$(which curl > /dev/null)
    IS_WGET_INSTALLED=$(which wget > /dev/null)

    if ${IS_CURL_INSTALLED}; then
        echo "OK - curl found"
     elif ${IS_WGET_INSTALLED}; then
        echo "OK - wget found"
     else
        echo "curl and wget not found. Curl or Wget is required to download the installer. Please install curl or wget."
    fi

    IS_GPG_INSTALLED=$(which gpg > /dev/null)
    if ${IS_GPG_INSTALLED}; then
        ${__INSTALLER_SKIP_SIGNATURE_VALIDATION} || echo "OK - gpg found"
     else
        ${__INSTALLER_SKIP_SIGNATURE_VALIDATION} || echo "gpg not found. GPG is required to verify the signature of the installer. Please install gpg."
    fi


    ${__INSTALLER_SKIP_SIGNATURE_VALIDATION} || \
    if test ! -f ${__INSTALLER_APP_PUBLIC_TRUSTED_KEYRING}; then
        # TODO
        __INSTALLER_SKIP_SIGNATURE_VALIDATION=true
        echo "### NOTE - Initial install detected ###"
        echo "### NOTE - For now we just skip signature validation for initial installs ###"
    fi
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


####################
# MAIN LOGIC
####################

# Check Installation status ()
check_installation_status

# Create temp dir and set trap to cleanup
trap cleanup EXIT INT QUIT TERM
tmpDir="$(mktemp -d -t ${__INSTALLER_PROJECT_NAME}-installer.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX \
    || stop_it "Can't create temporary directory for downloading ASV-SAM-Installer")"

# Git latest release of installer file
INSTALLER_URL=$(curl -sL ${__INSTALLER_GITHUB_RELEASE_URI} \
    | grep "browser_download_url.*${__INSTALLER_INSTALLER_FILENAME}" \
    | cut -d : -f 2,3 \
    | tr -d \")
if test "${INSTALLER_URL}" = ""; then
    stop_it "Could not create INSTALLER_URL for latest installer version.
This usually means the config provided to the INSTALL_WRAPPER is not correct (e.g. __INSTALLER_GITHUB_ORG_REPO_NAME, __INSTALLER_GITHUB_RELEASE_URI or __INSTALLER_INSTALLER_FILENAME) or no installer has been released yet on GitHub.
Please refer to if: ${__INSTALLER_GITHUB_URI}"
fi

# Get installer - Download in temp directory
echo "Download '${INSTALLER_URL}' to temporary file '${__INSTALLER_INSTALLER_FILENAME}' ..."
curl --fail -sL ${INSTALLER_URL} -o "$tmpDir/${__INSTALLER_INSTALLER_FILENAME}" \
    || stop_it "Could not load latest installer version from '${INSTALLER_URL}'. Please refer to: ${__INSTALLER_GITHUB_URI}"

# Get installer gpg signature - Download in temp directory
INSTALLER_SIG_URL=${INSTALLER_URL}.sig
${__INSTALLER_SKIP_SIGNATURE_VALIDATION} || \
    echo "Download '${INSTALLER_SIG_URL}' to temporary file '${__INSTALLER_INSTALLER_SIG_FILENAME}' ..."
${__INSTALLER_SKIP_SIGNATURE_VALIDATION} || \
    curl --fail -sL ${INSTALLER_SIG_URL} -o "$tmpDir/${__INSTALLER_INSTALLER_SIG_FILENAME}" \
        || stop_it "Could not load installer signature from '${INSTALLER_SIG_URL}'. Please refer to: ${__INSTALLER_GITHUB_URI}"

# Validate gpg signature of installer
${__INSTALLER_SKIP_SIGNATURE_VALIDATION} || validate_installer_signature "$tmpDir/${__INSTALLER_INSTALLER_FILENAME}" \
    || stop_it "Signature validation of Installer failed and we consider it as insecure."

# Run installer
$tmpDir/${__INSTALLER_INSTALLER_FILENAME}

# Cleanup - But should also happen via trap, but better be sure
cleanup

} # End of wrapping

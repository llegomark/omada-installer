#!/bin/bash
#title           :install-omada-controller.sh
#description     :Installer for TP-Link Omada Software Controller
#supported       :Ubuntu 20.04, Ubuntu 22.04, Ubuntu 24.04
#author          :monsn0
#date            :2021-07-29
#updated         :2024-05-23 # <-- Updated date

echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "TP-Link Omada Software Controller - Installer"
echo "https://github.com/monsn0/omada-installer"
echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"

echo "[+] Verifying running as root"
if [ `id -u` -ne 0 ]; then
  echo -e "\e[1;31m[!] Script requires to be ran as root. Please rerun using sudo. \e[0m"
  exit 1
fi

echo "[+] Verifying supported CPU"
if ! lscpu | grep -iq avx; then
    echo -e "\e[1;31m[!] Your CPU does not support AVX. MongoDB 5.0+ requires an AVX supported CPU. \e[0m"
    exit 1
fi

echo "[+] Verifying supported OS"
OS=$(hostnamectl status | grep "Operating System" | sed 's/^[ \t]*//')
echo "[~] $OS"

if [[ $OS = *"Ubuntu 20.04"* ]]; then
    OsVer=focal
elif [[ $OS = *"Ubuntu 22.04"* ]]; then
    OsVer=jammy
elif [[ $OS = *"Ubuntu 24.04"* ]]; then
    OsVer=noble
else
    echo -e "\e[1;31m[!] Script currently only supports Ubuntu 20.04, 22.04 or 24.04! \e[0m"
    exit 1
fi

echo "[+] Installing script prerequisites"
apt-get -qq update
# Added unzip
apt-get -qq install gnupg curl unzip &> /dev/null
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[!] Failed to install script prerequisites. Check apt output. \e[0m"
    # Try again with output visible
    apt-get install gnupg curl unzip
    if [ $? -ne 0 ]; then
      echo -e "\e[1;31m[!] Prerequisite installation failed again. Exiting. \e[0m"
      exit 1
    fi
fi


echo "[+] Importing the MongoDB 8.0 PGP key and creating the APT repository"
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $OsVer/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list
apt-get -qq update

echo "[+] Downloading the Omada Software Controller package (ZIP)"
# New URL for the ZIP file
OmadaZipPackageUrl="https://static.tp-link.com/upload/beta/2025/202505/20250514/Omada_SDN_Controller_v5.15.24.14_pre-release_linux_x64_deb.zip"
OmadaZipBasename=$(basename "$OmadaZipPackageUrl")
OmadaZipPath="/tmp/$OmadaZipBasename"
OmadaExtractDir="/tmp/omada_controller_extracted" # Directory to extract the zip

# Using -# for progress bar, -L to follow redirects, -o for output file
curl -# -Lo "$OmadaZipPath" "$OmadaZipPackageUrl"
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[!] Failed to download Omada Controller ZIP package from $OmadaZipPackageUrl. \e[0m"
    exit 1
fi

echo "[+] Extracting the Omada Software Controller .deb file"
mkdir -p "$OmadaExtractDir"
# -q for quiet, -o to overwrite existing files without prompting (good for reruns if needed)
# -d to specify extraction directory
unzip -qo "$OmadaZipPath" -d "$OmadaExtractDir"
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[!] Failed to unzip Omada Controller package. \e[0m"
    rm -f "$OmadaZipPath" # Clean up downloaded zip
    rm -rf "$OmadaExtractDir" # Clean up (potentially partially) extracted dir
    exit 1
fi

# Find the .deb file within the extracted directory
# Using -quit to stop after the first find; assumes only one .deb of interest
OmadaDebFile=$(find "$OmadaExtractDir" -name '*.deb' -print -quit)

if [ -z "$OmadaDebFile" ] || [ ! -f "$OmadaDebFile" ]; then
    echo -e "\e[1;31m[!] Could not find .deb file in the unzipped package at $OmadaExtractDir. \e[0m"
    ls -R "$OmadaExtractDir" # List contents for debugging
    rm -f "$OmadaZipPath"
    rm -rf "$OmadaExtractDir"
    exit 1
fi
OmadaDebBasename=$(basename "$OmadaDebFile")
echo "[~] Found .deb file: $OmadaDebFile"


# Package dependencies
echo "[+] Installing MongoDB 8.0"
apt-get -qq install mongodb-org # Removed &> /dev/null to see potential errors
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[!] Failed to install MongoDB. Check apt output. \e[0m"
    exit 1
fi

echo "[+] Installing OpenJDK 21 JRE (headless)"
apt-get -qq install openjdk-21-jre-headless # Removed &> /dev/null
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[!] Failed to install OpenJDK. Check apt output. \e[0m"
    exit 1
fi

echo "[+] Installing JSVC"
apt-get -qq install jsvc # Removed &> /dev/null
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[!] Failed to install JSVC. Check apt output. \e[0m"
    exit 1
fi

echo "[+] Installing Omada Software Controller $(echo "$OmadaDebBasename" | tr "_" "\n" | sed -n '4p')"
dpkg -i "$OmadaDebFile" # Removed &> /dev/null to see potential errors
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[!] Failed to install Omada Controller .deb package. \e[0m"
    echo -e "\e[1;33m[~] Attempting to fix broken dependencies with 'apt-get -f install'... \e[0m"
    apt-get -f -y install
    # Retry installing Omada if apt-get -f install succeeded
    if [ $? -eq 0 ]; then
        echo "[+] Retrying Omada Software Controller installation..."
        dpkg -i "$OmadaDebFile"
        if [ $? -ne 0 ]; then
            echo -e "\e[1;31m[!] Failed to install Omada Controller .deb package even after 'apt-get -f install'. \e[0m"
            # Clean up before exiting
            echo "[+] Cleaning up downloaded and extracted files..."
            rm -f "$OmadaZipPath"
            rm -rf "$OmadaExtractDir"
            exit 1
        fi
    else
        echo -e "\e[1;31m[!] 'apt-get -f install' failed. Cannot install Omada Controller. \e[0m"
        # Clean up before exiting
        echo "[+] Cleaning up downloaded and extracted files..."
        rm -f "$OmadaZipPath"
        rm -rf "$OmadaExtractDir"
        exit 1
    fi
fi


echo "[+] Cleaning up downloaded and extracted files..."
rm -f "$OmadaZipPath"
rm -rf "$OmadaExtractDir"

hostIP=$(hostname -I | awk '{print $1}') # awk '{print $1}' is more robust than cut
echo -e "\e[0;32m[~] Omada Software Controller has been successfully installed! :)\e[0m"
echo -e "\e[0;32m[~] Please visit https://${hostIP}:8043 to complete the inital setup wizard.\e[0m\n"

exit 0
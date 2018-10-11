#!/bin/bash
# © Copyright IBM Corporation 2017, 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

set -e

PACKAGE_NAME="phantomjs"
PACKAGE_VERSION="2.1.1"
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false
BUILD_DIR="/usr/local"
CONF_URL="https://raw.githubusercontent.com/sid226/scripts/master/PhantomJS/files"

trap "" 1 2 ERR

# Need handling for RHEL 6.10 as it  doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
	cat /etc/redhat-release >>"${LOG_FILE}"
	export ID="rhel"
	export VERSION_ID="6.x"
	export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function checkPrequisites() {
	# Check Sudo exist
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n'
	else
		printf -- 'Sudo : No \n'
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi
	
	if command -v "phantomjs" >/dev/null; then
		printf -- "Go : Yes" >>"$LOG_FILE"

		if phantomjs version | grep -q "$PACKAGE_VERSION"; then
			printf -- "Version : %s (Satisfied) \n" "${PACKAGE_VERSION}" | tee -a "$LOG_FILE"
			printf -- "No update required for Go \n" | tee -a "$LOG_FILE"
			exit 0
		fi
	fi
}

function cleanup() {
	rm -rf "${BUILD_DIR}/openssl"
	rm -rf "${BUILD_DIR}/curl"
	rm -rf "${BUILD_DIR}/curl/mk-ca-bundle.pl"
	rm -rf "${BUILD_DIR}/phantomjs"
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"

}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	if [[ "${OVERRIDE}" == "true" ]]; then
		printf -- 'phantomjs exists on the system. Override flag is set to true hence updating the same\n ' | tee -a "$LOG_FILE"
	fi

	if [[ "${VERSION_ID}" == "sles-15" ]]; then
		# Build OpenSSL 1.0.2
		cd "$BUILD_DIR"
		git clone git://github.com/openssl/openssl.git
		cd openssl
		git checkout OpenSSL_1_0_2l
		./config --prefix=/usr --openssldir=/usr/local/openssl shared
		make
		sudo make install

		# Build cURL 7.52.1
		cd "$BUILD_DIR"
		git clone git://github.com/curl/curl.git
		cd curl
		git checkout curl-7_52_1
		./buildconf
		./configure --prefix=/usr/local --with-ssl --disable-shared
		make && sudo make install
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib64
		export PATH=/usr/local/bin:$PATH

		# Generate ca-bundle.crt for curl
		echo insecure >>$HOME/.curlrc
		wget https://raw.githubusercontent.com/curl/curl/curl-7_53_0/lib/mk-ca-bundle.pl
		perl mk-ca-bundle.pl -k
		export SSL_CERT_FILE=$(pwd)/ca-bundle.crt
		rm $HOME/.curlrc

	fi

	# Install Phantomjs
    cd "$BUILD_DIR"
    git clone git://github.com/ariya/phantomjs.git
    cd phantomjs
    git checkout 2.1.1
    git submodule init
    git submodule update

  # Download  JSStringRef.h
  if [[ "${VERSION_ID}" == "sles-15" ]]; 
  then
  # get config file 
	wget -q $CONF_URL/JSStringRef.h
  # replace config file
  cp JSStringRef.h "${BUILD_DIR}phantomjs/src/qt/qtwebkit/Source/JavaScriptCore/API/JSStringRef.h"

  fi

  # Build Phantomjs
  python build.py

  # Add Phantomjs to /usr/bin
  cp "${BUILD_DIR}/phantomjs/bin/phantomjs" /usr/bin/

	#Clean up the downloaded zip
	cleanup

	#Verify if phantomjs is configured correctly	
	if  command -v "$PACKAGE_NAME" > /dev/null ; then		
    	printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
    else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME";
		exit 127;
	fi
}

function logDetails() {
	printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"

	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

	printf -- "Detected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  install.sh [-s <silent>] [-d <debug>] [-v package-version] [-o override] [-p check-prequisite]"
	echo "       default: If no -v specified, latest version will be installed"
	echo
}

while getopts "h?dopv:" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	v)
		PACKAGE_VERSION="$OPTARG"
		;;
	o)
		OVERRIDE=true
		;;
	p)
		checkPrequisites
		exit 0
		;;
	esac
done

function printSummary() {

	printf -- "\n\nUsage: \n"
	printf -- "\n\nTo run PhantomJS , run the following command: \n"
	printf -- "\n\nFor Ubuntu: \n"
	printf -- "\n\n  export QT_QPA_PLATFORM=offscreen \n"
	printf -- "    phantomjs &   (Run in background)  \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null

	printf -- 'Installing the PhantomJS from repository \n' | tee -a "$LOG_FILE"
	sudo sudo apt-get install -y phantomjs >/dev/null

	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for PhantomJS from repository \n' | tee -a "$LOG_FILE"
	sudo yum -y install gcc gcc-c++ make flex bison gperf ruby openssl-devel freetype-devel fontconfig-devel libicu-devel sqlite-devel libpng-devel libjpeg-devel libXfont.s390x libXfont-devel.s390x xorg-x11-utils.s390x xorg-x11-font-utils.s390x tzdata.noarch tzdata-java.noarch xorg-x11-fonts-Type1.noarch xorg-x11-font-utils.s390x python python-setuptools git wget tar >/dev/null
	configureAndInstall
	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for PhantomJS from repository \n' | tee -a "$LOG_FILE"

	if [[ "${VERSION_ID}" == "sles-12.3" ]]; then
		sudo zypper install -y gcc gcc-c++ make flex bison gperf ruby openssl-devel freetype-devel fontconfig-devel libicu-devel sqlite-devel libpng-devel libjpeg-devel python-setuptools git xorg-x11-devel xorg-x11-essentials xorg-x11-fonts xorg-x11 xorg-x11-util-devel libXfont-devel libXfont1 python python-setuptools >/dev/null
	else
		sudo zypper install -y gcc gcc-c++ make flex bison gperf ruby freetype2-devel fontconfig-devel libicu-devel sqlite3-devel libpng16-compat-devel libjpeg8-devel python2 python2-setuptools git xorg-x11-devel xorg-x11-essentials xorg-x11-fonts xorg-x11 xorg-x11-util-devel libXfont-devel libXfont1 autoconf automake libtool >/dev/null
	fi

	configureAndInstall
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary

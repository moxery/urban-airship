#!/bin/bash -ex

# Copyright 2009-2013 Urban Airship Inc. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# 2. Redistributions in binaryform must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided withthe distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


TARGET_NAME="AirshipLib"
TEMP_DIR=$(mktemp -d -t $TARGET_NAME)
PROJECT_PATH=`dirname $0`/AirshipLib.xcodeproj
XCODE_SETTINGS="${TEMP_DIR}/${TARGET_NAME}.settings"

# Query the Xcode Project for the current settings, based on the current target
# Dump the settings output as an awkdb into /tmp
xcodebuild -showBuildSettings -project $PROJECT_PATH -target $TARGET_NAME > ${XCODE_SETTINGS}
xcode_setting() {
    echo $(cat ${XCODE_SETTINGS} | awk "\$1 == \"${1}\" { print \$3 }")
}

SRCROOT=$(xcode_setting "SRCROOT")
EXECUTABLE_EXTENSION=$(xcode_setting "EXECUTABLE_EXTENSION")
EXECUTABLE_PREFIX=$(xcode_setting "EXECUTABLE_PREFIX")
PRODUCT_NAME=$(xcode_setting "PRODUCT_NAME")
BINARY_DIR="$SRCROOT/distribution_binaries"

lib_base_name="$(echo ${EXECUTABLE_PREFIX}${PRODUCT_NAME} | awk -F '-' '{print $1}')"
version="$(echo $PRODUCT_NAME | awk -F '-' '{print $2}')"

dest_lib_root="${SRCROOT}/../Airship"

# Remove old libraries
echo "remove old library $lib_base_name*.${EXECUTABLE_EXTENSION}"
find "$dest_lib_root" -d 1 -name "$lib_base_name*.${EXECUTABLE_EXTENSION}" -exec rm {} \;

# Copies the lib to the Airship folder for sample projects to use (not for packaging)
echo "copy *.$EXECUTABLE_EXTENSION from ${BINARY_DIR} to $dest_lib_root"
cp "${BINARY_DIR}"/*.$EXECUTABLE_EXTENSION "$dest_lib_root"

for sample_prj_root in "${SRCROOT}"/../*Sample
do
    sample_prj_name="$(basename "$sample_prj_root")"
    sample_prj_setting_file="$sample_prj_root/$sample_prj_name.xcodeproj/project.pbxproj"
    echo "update library reference in $sample_prj_setting_file"
	if [[ -f "$sample_prj_setting_file" ]]; then
        sed "s/\($lib_base_name[^ ]*-\)[0-9]*\.[0-9]*\.[0-9]*\(\.$EXECUTABLE_EXTENSION\)/\1$version\2/g" "$sample_prj_setting_file" > "$TEMP_DIR/$sample_prj_name.tmp"
        chgrp staff "$TEMP_DIR/$sample_prj_name.tmp"
	    mv "$TEMP_DIR/$sample_prj_name.tmp" "$sample_prj_setting_file"
	fi
done

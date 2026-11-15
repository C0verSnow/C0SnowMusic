#!/bin/bash
set -euo pipefail

# BeeWare's official helper packages extension modules as signed frameworks.
source "$PROJECT_DIR/Vendor/Python.xcframework/build/utils.sh"
export EXPANDED_CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad Hoc}"
mkdir -p "$CODESIGNING_FOLDER_PATH/app" "$CODESIGNING_FOLDER_PATH/app_packages"
rsync -a --delete "$PROJECT_DIR/MusicApp/Resources/Python/" "$CODESIGNING_FOLDER_PATH/app/"
rsync -a --delete --exclude '__pycache__' "$PROJECT_DIR/Vendor/python-packages/" "$CODESIGNING_FOLDER_PATH/app_packages/"
install_python Vendor/Python.xcframework app app_packages

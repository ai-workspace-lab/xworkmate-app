#!/bin/bash
# Script to add FFI framework to Xcode project
# Run this once to configure the project to link libcodex_ffi.dylib

PROJECT_FILE="project.pbxproj"

# Check if already added
if grep -q "libcodex_ffi.dylib" "$PROJECT_FILE" 2>/dev/null; then
    echo "FFI library already configured in project"
    exit 0
fi

echo "Note: This script is for reference."
echo "To add the FFI library manually in Xcode:"
echo ""
echo "1. Open Runner.xcodeproj in Xcode"
echo "2. Select Runner target"
echo "3. Go to Build Phases > Link Binary With Libraries"
echo "4. Click '+' and add 'libcodex_ffi.dylib'"
echo "5. Set 'Framework Search Paths' to include '\$(PROJECT_DIR)/Frameworks'"
echo "6. Set 'Runpath Search Paths' to include '@executable_path/../Frameworks'"
echo ""
echo "Alternatively, use the Podfile to add a vendored framework:"
echo ""
echo "  pod 'CodexFFI', :path => '../rust'"

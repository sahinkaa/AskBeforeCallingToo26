THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64e
TARGET = iphone:clang:latest:26.0
FINALPACKAGE = 1
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AskBeforeCallingToo26
AskBeforeCallingToo26_FILES = Engine/ABTCore.m Engine/ABTCallURL.m Engine/Runtime.m Settings/ABC26Model.m Settings/ABC26Store.m
AskBeforeCallingToo26_CFLAGS = -fobjc-arc -fstack-protector-strong -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/Settings
AskBeforeCallingToo26_FRAMEWORKS = UIKit Foundation CoreFoundation Contacts
AskBeforeCallingToo26_LIBRARIES = roothide
include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = AskBeforeCallingToo26Prefs
AskBeforeCallingToo26Prefs_FILES = Settings/ABC26Model.m Settings/ABC26Store.m Settings/ABC26Controller.m
AskBeforeCallingToo26Prefs_CFLAGS = -fobjc-arc -fstack-protector-strong -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations
AskBeforeCallingToo26Prefs_FRAMEWORKS = UIKit Foundation CoreFoundation Contacts ContactsUI
AskBeforeCallingToo26Prefs_PRIVATE_FRAMEWORKS = Preferences
AskBeforeCallingToo26Prefs_LIBRARIES = roothide
AskBeforeCallingToo26Prefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/Settings/vendor
AskBeforeCallingToo26Prefs_INSTALL_PATH = /Library/PreferenceBundles
AskBeforeCallingToo26Prefs_RESOURCE_DIRS = Settings/Resources
include $(THEOS_MAKE_PATH)/bundle.mk

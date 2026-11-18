ARCHS = armv7
TARGET = iphone:clang:latest:9.3
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RuntimeX
RuntimeX_FILES = Tweak.xm
RuntimeX_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
RuntimeX_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
RuntimeX_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += runtimexprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

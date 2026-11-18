ARCHS = armv7
TARGET = iphone:clang:latest:9.3

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RuntimeXPrefs
RuntimeXPrefs_FILES = RXPRootListController.m
RuntimeXPrefs_FRAMEWORKS = UIKit
RuntimeXPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

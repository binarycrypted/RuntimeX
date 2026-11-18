#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface RXPRootListController : PSListController
@end

@implementation RXPRootListController

- (BOOL)isRussian {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.binarycrypted.runtimex.plist"];
    return [prefs[@"langIndex"] integerValue] == 1;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        BOOL ru = [self isRussian];
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *g1 = [PSSpecifier groupSpecifierWithName:ru ? @"Основные параметры" : @"General"];
        [g1 setProperty:ru ? @"Изменения применяются при следующем запуске игры." : @"Changes take effect on next app launch." forKey:@"footerText"];
        [specs addObject:g1];

        PSSpecifier *sEnable = [PSSpecifier preferenceSpecifierNamed:ru ? @"Включить RuntimeX" : @"Enable RuntimeX" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [sEnable setProperty:@"com.binarycrypted.runtimex" forKey:@"defaults"];
        [sEnable setProperty:@"enabled" forKey:@"key"];
        [sEnable setProperty:@YES forKey:@"default"];
        [specs addObject:sEnable];

        PSSpecifier *sHideSys = [PSSpecifier preferenceSpecifierNamed:ru ? @"Скрывать в системных (com.apple.*)" : @"Hide in System Apps (com.apple.*)" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [sHideSys setProperty:@"com.binarycrypted.runtimex" forKey:@"defaults"];
        [sHideSys setProperty:@"hideInAppleApps" forKey:@"key"];
        [sHideSys setProperty:@YES forKey:@"default"];
        [specs addObject:sHideSys];

        PSSpecifier *sAutoRun = [PSSpecifier preferenceSpecifierNamed:ru ? @"Автозапуск autorun.hex" : @"Auto-Run autorun.hex on Launch" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [sAutoRun setProperty:@"com.binarycrypted.runtimex" forKey:@"defaults"];
        [sAutoRun setProperty:@"autoRunScript" forKey:@"key"];
        [sAutoRun setProperty:@NO forKey:@"default"];
        [specs addObject:sAutoRun];

        PSSpecifier *g2 = [PSSpecifier groupSpecifierWithName:ru ? @"Интерфейс и язык" : @"Appearance & Language"];
        [specs addObject:g2];

        PSSpecifier *sLang = [PSSpecifier preferenceSpecifierNamed:ru ? @"Язык / Language" : @"Language" target:self set:@selector(setLangPreference:specifier:) get:@selector(readPreferenceValue:) detail:[PSListItemsController class] cell:PSLinkListCell edit:nil];
        [sLang setProperty:@"com.binarycrypted.runtimex" forKey:@"defaults"];
        [sLang setProperty:@"langIndex" forKey:@"key"];
        [sLang setProperty:@0 forKey:@"default"];
        sLang.values = @[@0, @1];
        sLang.titleDictionary = @{@0: @"English", @1: @"Русский"};
        [specs addObject:sLang];

        PSSpecifier *sTheme = [PSSpecifier preferenceSpecifierNamed:ru ? @"Цветовая тема" : @"Console Theme" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:[PSListItemsController class] cell:PSLinkListCell edit:nil];
        [sTheme setProperty:@"com.binarycrypted.runtimex" forKey:@"defaults"];
        [sTheme setProperty:@"themeIndex" forKey:@"key"];
        [sTheme setProperty:@0 forKey:@"default"];
        sTheme.values = @[@0, @1, @2];
        sTheme.titleDictionary = @{@0: @"Matrix Green", @1: @"Cyberpunk Neon", @2: @"Hacker Amber"};
        [specs addObject:sTheme];

        PSSpecifier *g3 = [PSSpecifier groupSpecifierWithName:ru ? @"Действия и проект" : @"Actions & Project"];
        [specs addObject:g3];

        PSSpecifier *bReset = [PSSpecifier preferenceSpecifierNamed:ru ? @"Сбросить настройки" : @"Reset Settings" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        bReset->action = @selector(resetSettings);
        [specs addObject:bReset];

        PSSpecifier *bGit = [PSSpecifier preferenceSpecifierNamed:@"GitHub: binarycrypted/RuntimeX" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        bGit->action = @selector(openGitHub);
        [specs addObject:bGit];

        _specifiers = specs;
    }
    return _specifiers;
}

- (void)setLangPreference:(id)value specifier:(PSSpecifier *)specifier {
    [self setPreferenceValue:value specifier:specifier];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com"]];
}

- (void)resetSettings {
    NSString *prefsPath = @"/var/mobile/Library/Preferences/com.binarycrypted.runtimex.plist";
    [[NSFileManager defaultManager] removeItemAtPath:prefsPath error:nil];
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end

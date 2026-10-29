#import <UIKit/UIKit.h>
#import <Preferences/PSViewController.h>
#import <Contacts/Contacts.h>
#import <ContactsUI/ContactsUI.h>
#import <CoreFoundation/CoreFoundation.h>
#import <roothide.h>
#import "ABC26Model.h"
#import "ABC26Store.h"

static void ABC26Notify(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("net.tateu.askbeforecallingtoo11/preferences"), NULL, NULL, YES);
}
static void ABC26Alert(UIViewController *controller, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AskBeforeCalling Too 26" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@interface ABC26TextEditor : UIViewController
@property(nonatomic, strong) ABC26Store *store;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *initialValue;
@property(nonatomic, copy) NSString *placeholder;
@property(nonatomic, strong) UITextView *editor;
@end
@implementation ABC26TextEditor
- (void)loadView {
    UIView *view = [UIView new]; view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UILabel *hint = [UILabel new]; hint.text = self.placeholder; hint.numberOfLines = 0; hint.textColor = UIColor.secondaryLabelColor; hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; hint.translatesAutoresizingMaskIntoConstraints = NO;
    self.editor = [UITextView new]; self.editor.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.editor.text = self.initialValue ?: @""; self.editor.autocorrectionType = UITextAutocorrectionTypeNo; self.editor.autocapitalizationType = UITextAutocapitalizationTypeNone; self.editor.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:hint]; [view addSubview:self.editor]; self.view = view;
    [NSLayoutConstraint activateConstraints:@[[hint.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:16], [hint.leadingAnchor constraintEqualToAnchor:view.layoutMarginsGuide.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:view.layoutMarginsGuide.trailingAnchor], [self.editor.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:12], [self.editor.leadingAnchor constraintEqualToAnchor:view.layoutMarginsGuide.leadingAnchor], [self.editor.trailingAnchor constraintEqualToAnchor:view.layoutMarginsGuide.trailingAnchor], [self.editor.bottomAnchor constraintEqualToAnchor:view.keyboardLayoutGuide.topAnchor constant:-16]]];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
}
- (void)save {
    NSError *error = nil;
    if (![self.store saveValue:self.editor.text.length ? self.editor.text : nil key:self.key error:&error]) { ABC26Alert(self, error.localizedDescription ?: @"The text could not be saved."); return; }
    ABC26Notify();
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface ABC26PaneController : PSViewController <UITableViewDataSource, UITableViewDelegate, CNContactPickerDelegate>
@property(nonatomic, strong) UITableView *settingsTable;
@property(nonatomic, strong) ABC26Store *store;
@property(nonatomic, copy) NSDictionary *schema;
@property(nonatomic, copy) NSDictionary *settings;
@property(nonatomic, copy) NSArray<NSDictionary *> *groups;
@property(nonatomic, copy) NSString *page;
@property(nonatomic, copy) NSArray<NSString *> *contactIdentifiers;
@end
@implementation ABC26PaneController
- (void)loadView {
    self.page = self.page ?: @"root";
    self.settingsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.settingsTable.dataSource = self; self.settingsTable.delegate = self;
    self.settingsTable.rowHeight = UITableViewAutomaticDimension; self.settingsTable.estimatedRowHeight = 54;
    self.view = self.settingsTable;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.schema) {
        NSString *path = [[NSBundle bundleForClass:ABC26PaneController.class] pathForResource:@"ABC26Schema" ofType:@"plist"];
        self.schema = path ? [NSDictionary dictionaryWithContentsOfFile:path] : @{};
    }
    if (!self.store) self.store = [[ABC26Store alloc] initWithPath:jbroot(@"/var/mobile/Library/Preferences/net.tateu.askbeforecallingtoo11.plist") schema:self.schema];
    if ([self.page isEqual:@"root"]) {
        self.title = @"AskBeforeCalling Too 26";
        UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 90)];
        footer.numberOfLines = 3; footer.font = [UIFont systemFontOfSize:12]; footer.textAlignment = NSTextAlignmentCenter; footer.textColor = UIColor.secondaryLabelColor;
        footer.text = @"AskBeforeCalling Too 26\nOriginal idea by tateu\nRebuilt for iOS 26 by sahinkaa";
        self.settingsTable.tableFooterView = footer;
    } else if ([self.page isEqual:@"whitelist"]) self.title = @"Whitelist";
    else self.title = ABC26Label(self.schema, self.schema[@"strings"][@"title"], @"strings");
    [self reloadPage];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadPage]; }
- (void)reloadPage {
    if (!self.store) return;
    NSError *error = nil;
    NSDictionary *values = [self.store read:&error];
    if (!values) {
        self.groups = @[@{@"title": @"Settings Unavailable", @"rows": @[@{@"cell": @"Error", @"label": error.localizedDescription ?: @"The settings could not be read."}]}];
        self.settings = @{};
    } else {
        self.settings = values;
        if ([self.page isEqual:@"whitelist"]) {
            NSDictionary *whitelist = ABC26Whitelist(values);
            if (!whitelist) {
                self.groups = @[@{@"rows": @[@{@"cell": @"Error", @"label": @"The existing whitelist has an unsupported format and has not been changed."}]}];
                self.contactIdentifiers = @[];
            } else {
                self.contactIdentifiers = [[whitelist allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                    NSComparisonResult result = [whitelist[a] localizedCaseInsensitiveCompare:whitelist[b]];
                    return result == NSOrderedSame ? [a compare:b] : result;
                }];
                NSMutableArray *rows = [NSMutableArray new];
                for (NSString *identifier in self.contactIdentifiers) [rows addObject:@{@"cell": @"Contact", @"key": identifier, @"label": whitelist[identifier]}];
                if (!rows.count) [rows addObject:@{@"cell": @"Error", @"label": @"No whitelisted contacts"}];
                self.groups = @[@{@"rows": rows}];
            }
        } else self.groups = ABC26Sections(self.schema, self.page);
    }
    if ([self.page isEqual:@"whitelist"]) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear All" style:UIBarButtonItemStylePlain target:self action:@selector(confirmClearAll)];
        self.navigationItem.rightBarButtonItem.enabled = self.contactIdentifiers.count > 0;
    }
    [self.settingsTable reloadData];
    NSUInteger rows = 0; for (NSDictionary *group in self.groups) rows += [group[@"rows"] count];
    NSDictionary *report = @{@"build": @"1.0", @"page": self.page, @"rows": @(rows), @"preferencesPath": self.store.path, @"preferencesReadable": @(values != nil), @"schemaLoaded": @([self.schema[@"root"][@"items"] count] > 0)};
    NSString *logs = jbroot(@"/var/mobile/Library/Logs");
    [NSFileManager.defaultManager createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
    [report writeToFile:[logs stringByAppendingPathComponent:@"AskBeforeCalling26-Settings.plist"] atomically:YES];
}
- (id)valueForSetting:(NSString *)key {
    id value = self.settings[key];
    if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) return value;
    return ABC26Defaults(self.schema)[key];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)self.groups.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.groups[(NSUInteger)section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.groups[(NSUInteger)section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *title = self.groups[(NSUInteger)section][@"title"];
    if ([title isEqual:@"Ask Before"]) return @"Applies to outgoing actions in Phone, FaceTime, Messages and Apple Mail. Emergency calls bypass confirmation.";
    if ([title hasPrefix:@"Whitelist"]) return @"Listed contacts skip confirmation. With All Recipients Must Match off, one whitelisted recipient is enough to skip a group confirmation. Unknown recipients do not count as matches.";
    return nil;
}
- (NSDictionary *)rowAt:(NSIndexPath *)path { return self.groups[(NSUInteger)path.section][@"rows"][(NSUInteger)path.row]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *row = [self rowAt:path];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSString *kind = row[@"cell"], *key = row[@"key"];
    cell.textLabel.text = ABC26Label(self.schema, row[@"label"], self.page); cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 3;
    BOOL enabled = !row[@"enabled"] || [row[@"enabled"] boolValue];
    cell.userInteractionEnabled = enabled; cell.contentView.alpha = enabled ? 1 : 0.45;
    if ([kind isEqual:@"PSSwitchCell"]) {
        UISwitch *control = [UISwitch new]; control.on = [[self valueForSetting:key] boolValue]; control.enabled = enabled;
        __weak ABC26PaneController *weakSelf = self;
        [control addAction:[UIAction actionWithHandler:^(UIAction *action) {
            BOOL on = ((UISwitch *)action.sender).on;
            NSError *error = nil;
            if (![weakSelf.store saveValue:@(on) key:key error:&error]) ABC26Alert(weakSelf, error.localizedDescription ?: @"The setting could not be saved.");
            else ABC26Notify();
            [weakSelf reloadPage];
        }] forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqual:@"PSEditTextCell"]) {
        NSString *placeholder = ABC26Label(self.schema, row[@"placeholder"], self.page);
        id stored = self.settings[key];
        NSString *value = [stored isKindOfClass:NSString.class] ? stored : nil;
        cell.textLabel.text = [self.groups[(NSUInteger)path.section][@"title"] length] ? self.groups[(NSUInteger)path.section][@"title"] : @"Edit Text";
        cell.detailTextLabel.text = value.length ? value : placeholder;
        cell.detailTextLabel.textColor = value.length ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([kind isEqual:@"Contact"]) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqual:@"PSLinkCell"]) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    else if ([kind isEqual:@"PSButtonCell"]) cell.textLabel.textColor = UIColor.systemBlueColor;
    else cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)openPage:(NSString *)page {
    ABC26PaneController *next = [ABC26PaneController new]; next.page = page; next.schema = self.schema; next.store = self.store;
    [self.navigationController pushViewController:next animated:YES];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *row = [self rowAt:path];
    NSString *action = row[@"action"], *detail = row[@"detail"];
    if ([row[@"cell"] isEqual:@"PSEditTextCell"]) {
        ABC26TextEditor *editor = [ABC26TextEditor new]; editor.store = self.store; editor.key = row[@"key"];
        editor.title = self.groups[(NSUInteger)path.section][@"title"];
        id value = self.settings[editor.key]; editor.initialValue = [value isKindOfClass:NSString.class] ? value : @"";
        editor.placeholder = [ABC26Label(self.schema, row[@"placeholder"], self.page) stringByAppendingString:@"\n\nUse {recipient} for the destination. Clear the field to restore the default."];
        [self.navigationController pushViewController:editor animated:YES];
    } else if ([detail isEqual:@"ABCCustomStringsController"]) [self openPage:@"strings"];
    else if ([detail isEqual:@"ABCTWhitelistController"] || [action isEqual:@"removeContact"]) [self openPage:@"whitelist"];
    else if ([action isEqual:@"addContact"]) [self addContact];
}
- (void)addContact {
    NSError *error = nil;
    NSDictionary *settings = [self.store read:&error];
    if (!settings || !ABC26Whitelist(settings)) { ABC26Alert(self, error.localizedDescription ?: @"The existing whitelist has an unsupported format. It has not been changed."); return; }
    CNContactPickerViewController *picker = [CNContactPickerViewController new]; picker.delegate = self;
    picker.predicateForEnablingContact = [NSPredicate predicateWithFormat:@"phoneNumbers.@count > 0 OR emailAddresses.@count > 0"];
    picker.predicateForSelectionOfContact = [NSPredicate predicateWithValue:YES];
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)saveContacts:(NSArray<CNContact *> *)contacts {
    NSMutableDictionary *entries = [NSMutableDictionary new];
    NSMutableDictionary *addresses = [NSMutableDictionary new];
    for (CNContact *contact in contacts) {
        if (!contact.identifier.length) continue;
        NSString *name = nil;
        if ([contact areKeysAvailable:[CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName] ? @[[CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName]] : @[]]) name = [CNContactFormatter stringFromContact:contact style:CNContactFormatterStyleFullName];
        if (!name.length && [contact isKeyAvailable:CNContactNicknameKey]) name = contact.nickname;
        if (!name.length && [contact isKeyAvailable:CNContactOrganizationNameKey]) name = contact.organizationName;
        if (!name.length && [contact isKeyAvailable:CNContactPhoneNumbersKey]) name = [contact.phoneNumbers.firstObject.value stringValue];
        if (!name.length && [contact isKeyAvailable:CNContactEmailAddressesKey]) name = contact.emailAddresses.firstObject.value;
        entries[contact.identifier] = name.length ? name : @"No Name, No Number";
        NSMutableArray *values = [NSMutableArray new];
        if ([contact isKeyAvailable:CNContactPhoneNumbersKey]) for (CNLabeledValue<CNPhoneNumber *> *phone in contact.phoneNumbers) if (phone.value.stringValue.length) [values addObject:phone.value.stringValue];
        if ([contact isKeyAvailable:CNContactEmailAddressesKey]) for (CNLabeledValue<NSString *> *email in contact.emailAddresses) if (email.value.length) [values addObject:email.value];
        addresses[contact.identifier] = values;
    }
    NSError *error = nil;
    if (![self.store addWhitelist:entries addresses:addresses error:&error]) ABC26Alert(self, error.localizedDescription ?: @"The contacts could not be saved.");
    else ABC26Notify();
    [self reloadPage];
}
- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContact:(CNContact *)contact {
    [picker dismissViewControllerAnimated:YES completion:^{ [self saveContacts:@[contact]]; }];
}
- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContacts:(NSArray<CNContact *> *)contacts {
    NSArray *selected = [contacts copy];
    [picker dismissViewControllerAnimated:YES completion:^{ [self saveContacts:selected]; }];
}
- (void)contactPickerDidCancel:(CNContactPickerViewController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{ [self reloadPage]; }];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return [[[self rowAt:path] objectForKey:@"cell"] isEqual:@"Contact"]; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    NSString *identifier = [self rowAt:path][@"key"];
    NSError *error = nil;
    if (![self.store updateWhitelist:@{} removing:@[identifier] error:&error]) ABC26Alert(self, error.localizedDescription ?: @"The contact could not be removed.");
    else ABC26Notify();
    [self reloadPage];
}
- (void)confirmClearAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Whitelist?" message:@"Remove all listed contacts from this tweak’s whitelist? This does not delete contacts from your phone." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    NSArray *identifiers = [self.contactIdentifiers copy];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error = nil;
        if (![self.store updateWhitelist:@{} removing:identifiers error:&error]) ABC26Alert(self, error.localizedDescription ?: @"The whitelist could not be cleared.");
        else ABC26Notify();
        [self reloadPage];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
@interface ABC26RootController : ABC26PaneController
@end
@implementation ABC26RootController
@end

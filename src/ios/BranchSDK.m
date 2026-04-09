#import "BranchSDK.h"

NSString * const pluginVersion = @"%BRANCH_PLUGIN_VERSION%";

@interface BranchSDK()

@property (strong, nonatomic) NSString *deepLinkUrl;

- (void)doShareLinkResponse:(int)callbackId sendResponse:(NSDictionary*)response;

@end

@implementation BranchSDK

- (void)pluginInitialize
{
  self.branchUniversalObjArray = [[NSMutableArray alloc] init];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURLNotification:) name:CDVPluginHandleOpenURLNotification object:nil];
}

- (void)handleOpenURLNotification:(NSNotification*)notification
{
    NSURL* url = [notification object];
    [[Branch getInstance] application:[UIApplication sharedApplication]  openURL:url options:@{}];
}

#pragma mark - Private APIs
#pragma mark - Global Instance Accessors

- (Branch *)getInstance
{
  return [Branch getInstance];
}

- (Branch *)getInstance:(NSString *)branchKey
{
  if (branchKey) {
    return [Branch getInstance:branchKey];
  }
  else {
    return [Branch getInstance];
  }
}

- (Branch *)getTestInstance
{
  return [Branch getTestInstance];
}

#pragma mark - Deep Linking Handlers

- (id)handleDeepLink:(CDVInvokedUrlCommand*)command
{
  NSString *arg = [command.arguments objectAtIndex:0];
  NSURL *url = [NSURL URLWithString:arg];
  self.deepLinkUrl = [url absoluteString];

  return [NSNumber numberWithBool:[[Branch getInstance] handleDeepLink:url]];
}

- (id)handleDeepLinkWithNewSession:(CDVInvokedUrlCommand*)command
{
  NSString *arg = [command.arguments objectAtIndex:0];
  NSURL *url = [NSURL URLWithString:arg];
  self.deepLinkUrl = [url absoluteString];

  return [NSNumber numberWithBool:[[Branch getInstance] handleDeepLinkWithNewSession:url]];
}

- (void)continueUserActivity:(CDVInvokedUrlCommand*)command
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *activityType = nil;
        if (command.arguments.count > 0 && [command.arguments[0] isKindOfClass:[NSString class]]) {
            activityType = (NSString *)command.arguments[0];
        }

        NSDictionary *userInfo = nil;
        if (command.arguments.count > 1 && [command.arguments[1] isKindOfClass:[NSDictionary class]]) {
            userInfo = (NSDictionary *)command.arguments[1];
        }

        NSString *optionalURLString = nil;
        if (command.arguments.count > 2 && [command.arguments[2] isKindOfClass:[NSString class]]) {
            optionalURLString = (NSString *)command.arguments[2];
        }

        // Default to browsing web if caller passed nil/empty.
        if (activityType.length == 0) {
            activityType = NSUserActivityTypeBrowsingWeb;
        }

        NSUserActivity *userActivity = [[NSUserActivity alloc] initWithActivityType:activityType];

        if (userInfo) {
            userActivity.userInfo = userInfo;
        }

        // If we're simulating a Universal Link, set webpageURL explicitly when provided.
        if ([activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && optionalURLString.length > 0) {
            NSURL *webURL = [NSURL URLWithString:optionalURLString];
            if (webURL) {
                userActivity.webpageURL = webURL;
                self.deepLinkUrl = webURL.absoluteString;
            }
        }

        [[Branch getInstance] continueUserActivity:userActivity];
    });
}


#pragma mark - Public APIs
#pragma mark - Branch Basic Methods

- (void)enableTestMode:(CDVInvokedUrlCommand*)command
{
  [Branch setUseTestBranchKey:TRUE];
}

- (void)initSession:(CDVInvokedUrlCommand*)command
{
  [[Branch getInstance] registerPluginName:@"CordovaIonic" version:pluginVersion];
  [[Branch getInstance] initSessionWithLaunchOptions:nil andRegisterDeepLinkHandler:^(NSDictionary *params, NSError *error) {

    NSString *resultString = nil;
    CDVPluginResult *pluginResult = nil;

    if (!error) {
      if (params != nil && [params count] > 0) {

        NSError *err;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&err];

        if (!jsonData) {
          NSLog(@"Parsing Error: %@", [err localizedDescription]);
          NSDictionary *errorDict = [NSDictionary dictionaryWithObjectsAndKeys:[err localizedDescription], @"error", nil];
          NSData* errorJSON = [NSJSONSerialization dataWithJSONObject:errorDict options:NSJSONWritingPrettyPrinted error:&err];

          resultString = [[NSString alloc] initWithData:errorJSON encoding:NSUTF8StringEncoding];
          pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:resultString];
        } else {
          resultString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
          pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:params];
        }
      }
    }
    else {
      NSLog(@"Init Error: %@", [error localizedDescription]);

      // We create a JSON string result, because we're getting an error if we directly return a string result.
      NSDictionary *errorDict = [NSDictionary dictionaryWithObjectsAndKeys:[error localizedDescription], @"error", nil];
      NSData* errorJSON = [NSJSONSerialization dataWithJSONObject:errorDict options:NSJSONWritingPrettyPrinted error:&error];

      resultString = [[NSString alloc] initWithData:errorJSON encoding:NSUTF8StringEncoding];
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:resultString];
    }

    if (command != nil) {
      [self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
    }
  }];
}

#pragma mark - Helpers

/// Minimal helper: builds a launchOptions dictionary.
/// - If `url` is non-nil, includes UIApplicationLaunchOptionsURLKey.
/// - Always returns a dictionary (never nil) to avoid nil-handling edge cases in SDK code paths.
- (NSDictionary *)bnc_launchOptionsForURL:(NSURL * _Nullable)url
{
    if (url) {
        return @{ UIApplicationLaunchOptionsURLKey: url };
    }
    return @{};
}


- (void)forceNewSession:(CDVInvokedUrlCommand*)command
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1) Resolve input URL string (prefer explicit arg[0], else self.deepLinkUrl).
        NSString *explicitURLString = nil;
        if (command.arguments.count > 0 && [command.arguments[0] isKindOfClass:[NSString class]]) {
            explicitURLString = (NSString *)command.arguments[0];
        }

        NSString *resolvedURLString = (explicitURLString.length > 0)
            ? explicitURLString
            : self.deepLinkUrl;

        NSURL *resolvedURL = (resolvedURLString.length > 0)
            ? [NSURL URLWithString:resolvedURLString]
            : nil;

        // If a URL string was provided but is not parseable, fail fast with ERROR.
        if (resolvedURLString.length > 0 && resolvedURL == nil) {
            NSString *errMsg = [NSString stringWithFormat:@"Invalid URL string: %@", resolvedURLString];
            CDVPluginResult *pluginResult =
                [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errMsg];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        // Persist the chosen URL back onto self.deepLinkUrl (useful for subsequent calls without args).
        if (resolvedURLString.length > 0) {
            self.deepLinkUrl = resolvedURLString;
        }

        // 2) Build launchOptions (URLKey only when URL exists).
        NSDictionary *launchOptions = [self bnc_launchOptionsForURL:resolvedURL];

        // 3) Register plugin name/version (kept consistent with existing initSession pattern).
        Branch *branch = [Branch getInstance];
        [branch registerPluginName:@"CordovaIonic" version:pluginVersion];

        // Branch initSession callbacks can occur multiple times; ensure we respond only once.
        __block BOOL didRespondToJS = NO;

        // If we have a URL, initSession may callback immediately with old params before we trigger a deep link restart.
        // We ignore callbacks until after we trigger handleDeepLinkWithNewSession.
        __block BOOL didTriggerDeepLinkRestart = NO;

        // 4) Register deep link handler that will return params (or error) back to JS.
        [branch initSessionWithLaunchOptions:launchOptions
                andRegisterDeepLinkHandler:^(NSDictionary *params, NSError *error) {

            // Ensure all Cordova responses go out on main.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (didRespondToJS) {
                    return;
                }

                // If a URL-driven restart is intended, ignore any callback that happens
                // before we actually trigger the restart.
                if (resolvedURL != nil && !didTriggerDeepLinkRestart) {
                    return;
                }

                didRespondToJS = YES;

                if (error) {
                    NSString *msg = error.localizedDescription ?: @"Branch initSession failed with an unknown error.";
                    CDVPluginResult *pluginResult =
                        [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:msg];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    return;
                }

                NSDictionary *safeParams = (params && [params isKindOfClass:[NSDictionary class]]) ? params : @{};

                // If Branch provides a referring link, prefer storing it as the current deepLinkUrl
                // (useful if JS calls forceNewSession() later without passing a URL).
                id referring = safeParams[@"~referring_link"];
                if ([referring isKindOfClass:[NSString class]] && [(NSString *)referring length] > 0) {
                    self.deepLinkUrl = (NSString *)referring;
                }

                CDVPluginResult *pluginResult =
                    [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:safeParams];

                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            });
        }];

        // 5) If a URL is present, explicitly force Branch to treat it as a new deep link session now.
        // Per Branch SDK source, handleDeepLinkWithNewSession currently routes to handleDeepLink and
        // resets initialization status to allow foreground links to callback, then triggers a new open. citeturn30view0turn28view0
        if (resolvedURL != nil) {
            didTriggerDeepLinkRestart = YES;
            [branch handleDeepLinkWithNewSession:resolvedURL];
        } else {
            // No URL available: allow the initSession call above to behave like a fresh open attempt.
            // (We intentionally do not logout.)
            didTriggerDeepLinkRestart = YES;
        }
    });
}


- (void)setRequestMetadata:(CDVInvokedUrlCommand*)command
{

  [[Branch getInstance] setRequestMetadataKey:[command.arguments objectAtIndex:0] value:[command.arguments objectAtIndex:1]];

}

- (void)disableTracking:(CDVInvokedUrlCommand*)command
{

  bool enabled = [[command.arguments objectAtIndex:0] boolValue];
  [Branch setTrackingDisabled:enabled];

  CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:enabled];

  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)enableLogging:(CDVInvokedUrlCommand*)command
{
  bool enableLogging = [[command.arguments objectAtIndex:0] boolValue];
  if (enableLogging) {
    [[Branch getInstance] enableLogging];
  }

  CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:enableLogging];

  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getAutoInstance:(CDVInvokedUrlCommand*)command
{
  [self initSession:nil];
}

- (void)getLatestReferringParams:(CDVInvokedUrlCommand*)command
{
  Branch *branch = [self getInstance];
  NSDictionary *sessionParams = [branch getLatestReferringParams];

  CDVPluginResult* pluginResult = nil;

  if (sessionParams != nil && [sessionParams count] > 0) {
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:sessionParams];
  } else {
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:FALSE];
  }
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getFirstReferringParams:(CDVInvokedUrlCommand*)command
{
  Branch *branch = [self getInstance];
  NSDictionary *installParams = [branch getFirstReferringParams];

  CDVPluginResult* pluginResult = nil;

  if (installParams != nil && [installParams count] > 0) {
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:installParams];
  } else {
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:FALSE];
  }
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setIdentity:(CDVInvokedUrlCommand*)command
{
  Branch *branch = [self getInstance];

  [branch setIdentity:[command.arguments objectAtIndex:0] withCallback:^(NSDictionary *params, NSError *error) {

    CDVPluginResult* pluginResult = nil;
    if (!error) {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:params];
    }
    else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }];
}

- (void)registerDeepLinkController:(CDVInvokedUrlCommand*)command
{
  UIViewController<BranchDeepLinkingController> *controller = (UIViewController<BranchDeepLinkingController>*)self.viewController;
  Branch *branch = [self getInstance];
  [branch registerDeepLinkController:controller forKey:[command.arguments objectAtIndex:0]];
}

-(void)sendBranchEvent:(CDVInvokedUrlCommand*)command
{
    NSString *eventName = [command.arguments objectAtIndex:0];
    NSDictionary *metadata;
    if ([command.arguments count] == 2) {
        metadata = [command.arguments objectAtIndex:1];
    }
    BranchEvent *event = [BranchEvent customEventWithName:eventName];
    for (id key in metadata) {
        if ([key isEqualToString:@"transactionID"]) {
            event.transactionID = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"currency"]) {
            event.currency = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"shipping"]) {
            NSString *value = ([[metadata objectForKey:key] isKindOfClass:[NSString class]]) ? [metadata objectForKey:key] : [[metadata objectForKey:key] stringValue];
            event.shipping = [NSDecimalNumber decimalNumberWithString:value];
        }
        else if ([key isEqualToString:@"tax"]) {
            NSString *value = ([[metadata objectForKey:key] isKindOfClass:[NSString class]]) ? [metadata objectForKey:key] : [[metadata objectForKey:key] stringValue];
            event.tax = [NSDecimalNumber decimalNumberWithString:value];
        }
        else if ([key isEqualToString:@"coupon"]) {
            event.coupon = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"affiliation"]) {
            event.affiliation = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"eventDescription"]) {
            event.eventDescription = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"revenue"]) {
            NSString *value = ([[metadata objectForKey:key] isKindOfClass:[NSString class]]) ? [metadata objectForKey:key] : [[metadata objectForKey:key] stringValue];
            event.revenue = [NSDecimalNumber decimalNumberWithString:value];
        }
        else if ([key isEqualToString:@"searchQuery"]) {
            event.searchQuery = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"description"]) {
            event.eventDescription = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"customerEventAlias"]) {
            event.alias = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"customData"] && [[metadata objectForKey:key] isKindOfClass:[NSMutableDictionary class]]) {
            event.customData = [metadata objectForKey:key];
        }
        else if ([key isEqualToString:@"contentMetadata"]){
             NSMutableArray *mArray = [[NSMutableArray alloc]init];

             for (NSDictionary *dataDictionary in [metadata objectForKey:key]){
                 BranchUniversalObject *contentItem = [BranchUniversalObject objectWithDictionary:(dataDictionary)];
                 [mArray addObject:contentItem];
             }
             event.contentItems = [mArray copy];
        }
    }
    [event logEvent];
}


- (void)logout:(CDVInvokedUrlCommand*)command
{
  Branch *branch = [self getInstance];
  [branch logoutWithCallback:^(BOOL changed, NSError *error) {
    CDVPluginResult *pluginResult = nil;
    if (!error) {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:changed];
    } else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }];
  self.branchUniversalObjArray = [[NSMutableArray alloc] init];
}

- (void)setDMAParamsForEEA:(CDVInvokedUrlCommand*)command {
  if (command.arguments.count < 3) {
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Insufficient arguments"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    return;
  }

  BOOL eeaRegion = [[command.arguments objectAtIndex:0] boolValue];
  BOOL adPersonalizationConsent = [[command.arguments objectAtIndex:1] boolValue];
  BOOL adUserDataUsageConsent = [[command.arguments objectAtIndex:2] boolValue];

  [Branch setDMAParamsForEEA:eeaRegion AdPersonalizationConsent:adPersonalizationConsent AdUserDataUsageConsent:adUserDataUsageConsent];

  CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setConsumerProtectionAttributionLevel:(CDVInvokedUrlCommand*)command {
    NSString *level = [command.arguments objectAtIndex:0];
    BranchAttributionLevel attributionLevel;
    
    if ([level isEqualToString:@"FULL"]) {
        attributionLevel = BranchAttributionLevelFull;
    } else if ([level isEqualToString:@"REDUCED"]) {
        attributionLevel = BranchAttributionLevelReduced;
    } else if ([level isEqualToString:@"MINIMAL"]) {
        attributionLevel = BranchAttributionLevelMinimal;
    } else if ([level isEqualToString:@"NONE"]) {
        attributionLevel = BranchAttributionLevelNone;
    } else {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR 
                                                        messageAsString:@"Invalid attribution level"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
    
    [[Branch getInstance] setConsumerProtectionAttributionLevel:attributionLevel];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - Branch Universal Object Methods

- (void)createBranchUniversalObject:(CDVInvokedUrlCommand*)command
{
  NSDictionary *properties = [command.arguments objectAtIndex:0];
  BranchUniversalObject *branchUniversalObj = [[BranchUniversalObject alloc] init];

  for (id key in properties) {
    if ([key isEqualToString:@"contentMetadata"]){
        NSMutableDictionary<NSString *,NSString *> *metadata = (NSMutableDictionary<NSString *,NSString *> *)[properties valueForKey:key];
        [[branchUniversalObj contentMetadata] setCustomMetadata:metadata];
    }
    else if ([key isEqualToString:@"contentIndexingMode"]) {
      NSString *indexingMode = [properties valueForKey:key];
      // Default contentIndexMode is always public
      if ([indexingMode isEqualToString:@"private"]) {
        branchUniversalObj.publiclyIndex = false;
      }
      else {
        branchUniversalObj.publiclyIndex = true;
      }
    }
    else if ([key isEqualToString:@"canonicalIdentifier"]) {
      branchUniversalObj.canonicalIdentifier = [properties valueForKey:key];
    }
    else if ([key isEqualToString:@"title"]) {
      branchUniversalObj.title = [properties valueForKey:key];
    }
    else if ([key isEqualToString:@"contentDescription"]) {
      branchUniversalObj.contentDescription = [properties valueForKey:key];
    }
    else if ([key isEqualToString:@"contentImageUrl"]){
      NSString *imageUrl = [properties valueForKey:key];
      branchUniversalObj.imageUrl = imageUrl;
    }
    else {
      [branchUniversalObj setValue:[properties objectForKey:key] forKey:key];
    }
  }

  // [self.branchUniversalObjArray addObject:branchUniversalObj];

  // Instantiate callback ids
  NSMutableDictionary *branchUniversalObjDict = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                                @"branchUniversalObj": branchUniversalObj,
                                                                                                @"onShareSheetDismissed": command.callbackId,
                                                                                                @"onShareSheetLaunched": command.callbackId,
                                                                                                @"onLinkShareResponse": command.callbackId,
                                                                                                @"onChannelSelected": command.callbackId
                                                                                                }];
  [self.branchUniversalObjArray addObject:branchUniversalObjDict];

  NSNumber *branchUniversalObjectId = [[NSNumber alloc] initWithInteger:([self.branchUniversalObjArray count] - 1)];
  NSString *message = @"createBranchUniversalObject Success";
  NSDictionary *params = [[NSDictionary alloc] initWithObjectsAndKeys:message, @"message", branchUniversalObjectId, @"branchUniversalObjectId", nil];

  CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:params];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)registerView:(CDVInvokedUrlCommand*)command
{
  int branchUniversalObjectId = [[command.arguments objectAtIndex:0] intValue];

  NSMutableDictionary *branchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:branchUniversalObjectId];
  BranchUniversalObject *branchUniversalObj = [branchUniversalObjDict objectForKey:@"branchUniversalObj"];

  [branchUniversalObj registerViewWithCallback:^(NSDictionary *params, NSError *error) {
    CDVPluginResult *pluginResult = nil;
    if (!error) {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:params];
    } else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }];
}

- (void)generateShortUrl:(CDVInvokedUrlCommand*)command
{

  int branchUniversalObjectId = [[command.arguments objectAtIndex:0] intValue];
  NSDictionary *arg1 = [command.arguments objectAtIndex:1];
  NSDictionary *arg2 = [command.arguments objectAtIndex:2];

  NSMutableDictionary *branchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:branchUniversalObjectId];
  BranchUniversalObject *branchUniversalObj = [branchUniversalObjDict objectForKey:@"branchUniversalObj"];

  BranchLinkProperties *props = [[BranchLinkProperties alloc] init];

  for (id key in arg1) {
    if ([key isEqualToString:@"duration"]) {
      props.matchDuration = (NSUInteger)[((NSNumber *)[arg1 objectForKey:key]) integerValue];
    }
    else if ([key isEqualToString:@"feature"]) {
      props.feature = [arg1 objectForKey:key];
    }
    else if ([key isEqualToString:@"stage"]) {
      props.stage = [arg1 objectForKey:key];
    }
    else if ([key isEqualToString:@"campaign"]) {
      props.campaign = [arg1 objectForKey:key];
    }
    else if ([key isEqualToString:@"alias"]) {
      props.alias = [arg1 objectForKey:key];
    }
    else if ([key isEqualToString:@"channel"]) {
      props.channel = [arg1 objectForKey:key];
    }
    else if ([key isEqualToString:@"tags"] && [[arg1 objectForKey:key] isKindOfClass:[NSArray class]]) {
      props.tags = [arg1 objectForKey:key];
    }
  }
  if (arg2) {
    for (id key in arg2) {
      [props addControlParam:key withValue:[arg2 objectForKey:key]];
    }
  }

  [branchUniversalObj getShortUrlWithLinkProperties:props andCallback:^(NSString *url, NSError *error) {
    CDVPluginResult* pluginResult = nil;

    if (url) {
      NSError *err;
      NSDictionary *jsonObj = [[NSDictionary alloc] initWithObjectsAndKeys:url, @"url", 0, @"options", &err, @"error", nil];

      if (!jsonObj) {
        NSLog(@"Parsing Error: %@", [err localizedDescription]);
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[err localizedDescription]];
      } else {
        NSLog(@"Success");
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:jsonObj];
      }
    }
    else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }];
}

- (void)showShareSheet:(CDVInvokedUrlCommand*)command
{
  NSString *shareText = @"Share Link";

  if ([command.arguments count] >= 4) {
    shareText = [command.arguments objectAtIndex:3];
  }

  int branchUniversalObjectId = [[command.arguments objectAtIndex:0] intValue];
  NSDictionary *arg1 = [command.arguments objectAtIndex:1];
  NSDictionary *arg2 = [command.arguments objectAtIndex:2];

  NSMutableDictionary *branchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:branchUniversalObjectId];
  BranchUniversalObject *branchUniversalObj = [branchUniversalObjDict objectForKey:@"branchUniversalObj"];

  BranchLinkProperties *linkProperties = [[BranchLinkProperties alloc] init];

  for (id key in arg1) {
    if ([key isEqualToString:@"duration"]) {
      linkProperties.matchDuration = (NSUInteger)[((NSNumber *)[arg1 objectForKey:key]) integerValue];
    }
    else {
      [linkProperties setValue:[arg1 objectForKey:key] forKey:key];
    }
  }

  if (arg2) {
    for (id key in arg2) {
      [linkProperties addControlParam:key withValue:[arg2 objectForKey:key]];
    }
  }
    [branchUniversalObj showShareSheetWithLinkProperties:linkProperties andShareText:shareText fromViewController:self.viewController completionWithError:^(NSString * _Nullable activityType, BOOL completed, NSError * _Nullable error) {
        
        int listenerCallbackId = [[command.arguments objectAtIndex:0] intValue];

        if (completed) {
          NSLog(@"Share link complete");
          [branchUniversalObj getShortUrlWithLinkProperties:linkProperties andCallback:^(NSString *url, NSError *error) {
            if (!error) {
              NSDictionary *response = [[NSDictionary alloc] initWithObjectsAndKeys:url, @"sharedLink", activityType, @"sharedChannel", nil];
              [self doShareLinkResponse:listenerCallbackId sendResponse:response];
            }
          }];
        }

    CDVPluginResult *shareDialogDismissed = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];

    NSMutableDictionary *branchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:listenerCallbackId];

    [shareDialogDismissed setKeepCallbackAsBool:TRUE];

    [self.commandDelegate sendPluginResult:shareDialogDismissed callbackId:[branchUniversalObjDict objectForKey:@"onShareSheetDismissed"]];
  }];
}

- (void)doShareLinkResponse:(int)callbackId sendResponse:(NSDictionary*)response {
  CDVPluginResult *linkShareResponse = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
  NSMutableDictionary *branchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:callbackId];

  [linkShareResponse setKeepCallbackAsBool:TRUE];

  [self.commandDelegate sendPluginResult:linkShareResponse callbackId:[branchUniversalObjDict objectForKey:@"onLinkShareResponse"]];
}

- (void)onShareLinkDialogDismissed:(CDVInvokedUrlCommand*)command
{
  int listenerCallbackId = [[command.arguments objectAtIndex:0] intValue];

  NSMutableDictionary *newBranchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:listenerCallbackId];
  [newBranchUniversalObjDict setObject:command.callbackId forKey:@"onShareSheetDismissed"];

  [self.branchUniversalObjArray replaceObjectAtIndex:listenerCallbackId withObject:newBranchUniversalObjDict];
}

- (void)onLinkShareResponse:(CDVInvokedUrlCommand*)command
{
  int listenerCallbackId = [[command.arguments objectAtIndex:0] intValue];

  NSMutableDictionary *newBranchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:listenerCallbackId];
  [newBranchUniversalObjDict setObject:command.callbackId forKey:@"onLinkShareResponse"];

  [self.branchUniversalObjArray replaceObjectAtIndex:listenerCallbackId withObject:newBranchUniversalObjDict];
}

- (void)listOnSpotlight:(CDVInvokedUrlCommand*)command {
  int branchUniversalObjectId = [[command.arguments objectAtIndex:0] intValue];

  NSMutableDictionary *branchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:branchUniversalObjectId];
  BranchUniversalObject *branchUniversalObj = [branchUniversalObjDict objectForKey:@"branchUniversalObj"];

  [branchUniversalObj listOnSpotlightWithCallback:^(NSString *string, NSError *error) {
    CDVPluginResult* pluginResult = nil;
    if (!error) {
      NSError *err;
      NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"result":string} options:0 error:&err];
      if (!jsonData) {
        NSLog(@"Parsing Error: %@", [err localizedDescription]);
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[err localizedDescription]];
      } else {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
      }
    }
    else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }];
}

#pragma mark Branch Query Methods

- (void)lastAttributedTouchData:(CDVInvokedUrlCommand *)command {
  NSMutableDictionary *json = [NSMutableDictionary new];

  Branch *branch = [self getInstance];
  [branch lastAttributedTouchDataWithAttributionWindow:30 completion:^(BranchLastAttributedTouchData * _Nullable latd, NSError * _Nullable error) {
    CDVPluginResult* pluginResult = nil;
    if (latd) {
      [json setObject:latd.attributionWindow forKey:@"attribution_window"];
      [json setObject:latd.lastAttributedTouchJSON forKey:@"last_attributed_touch_data"];

      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:json];
    } else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No LATD available"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }];
}

- (void)getBranchQRCode:(CDVInvokedUrlCommand*)command
{
    int branchUniversalObjectId = [[command.arguments objectAtIndex:1] intValue];
    NSMutableDictionary *branchUniversalObjDict = [self.branchUniversalObjArray objectAtIndex:branchUniversalObjectId];
    BranchUniversalObject *branchUniversalObj = [branchUniversalObjDict objectForKey:@"branchUniversalObj"];

    BranchLinkProperties *linkProperties = [BranchLinkProperties new];
    
    NSDictionary *arg1 = [command.arguments objectAtIndex:2];
    NSDictionary *arg2 = [command.arguments objectAtIndex:3];

    for (id key in arg1) {
      if ([key isEqualToString:@"duration"]) {
        linkProperties.matchDuration = (NSUInteger)[((NSNumber *)[arg1 objectForKey:key]) integerValue];
      }
      else if ([key isEqualToString:@"feature"]) {
        linkProperties.feature = [arg1 objectForKey:key];
      }
      else if ([key isEqualToString:@"stage"]) {
        linkProperties.stage = [arg1 objectForKey:key];
      }
      else if ([key isEqualToString:@"campaign"]) {
        linkProperties.campaign = [arg1 objectForKey:key];
      }
      else if ([key isEqualToString:@"alias"]) {
        linkProperties.alias = [arg1 objectForKey:key];
      }
      else if ([key isEqualToString:@"channel"]) {
        linkProperties.channel = [arg1 objectForKey:key];
      }
      else if ([key isEqualToString:@"tags"] && [[arg1 objectForKey:key] isKindOfClass:[NSArray class]]) {
        linkProperties.tags = [arg1 objectForKey:key];
      }
    }
    if (arg2) {
      for (id key in arg2) {
        [linkProperties addControlParam:key withValue:[arg2 objectForKey:key]];
      }
    }

    NSMutableDictionary *qrCodeSettingsMap = [command.arguments objectAtIndex:0];

    BranchQRCode *qrCode = [BranchQRCode new];
    
    if (qrCodeSettingsMap[@"codeColor"]) {
        qrCode.codeColor = [self colorWithHexString:qrCodeSettingsMap[@"codeColor"]];
    }
    if (qrCodeSettingsMap[@"backgroundColor"]) {
        qrCode.backgroundColor = [self colorWithHexString:qrCodeSettingsMap[@"backgroundColor"]];
    }
    if (qrCodeSettingsMap[@"centerLogo"]) {
        qrCode.centerLogo = qrCodeSettingsMap[@"centerLogo"];
    }
    if (qrCodeSettingsMap[@"width"]) {
        qrCode.width = qrCodeSettingsMap[@"width"];
    }
    if (qrCodeSettingsMap[@"margin"]) {
        qrCode.margin = qrCodeSettingsMap[@"margin"];
    }
    if (qrCodeSettingsMap[@"imageFormat"]) {
        if ([qrCodeSettingsMap[@"imageFormat"] isEqual:@"JPEG"]) {
            qrCode.imageFormat = BranchQRCodeImageFormatJPEG;
        } else {
            qrCode.imageFormat = BranchQRCodeImageFormatPNG;
        }
    }

    [qrCode getQRCodeAsData:branchUniversalObj linkProperties:linkProperties completion:^(NSData * _Nonnull qrCodeData, NSError * _Nonnull error) {
      CDVPluginResult* pluginResult = nil;
        
        if (!error) {
            NSString* imageString = [qrCodeData base64EncodedStringWithOptions:nil];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:imageString];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (UIColor *) colorWithHexString: (NSString *) hexString {
    NSString *colorString = [[hexString stringByReplacingOccurrencesOfString: @"#" withString: @""] uppercaseString];
    CGFloat alpha, red, blue, green;
    switch ([colorString length]) {
        case 3: // #RGB
            alpha = 1.0f;
            red   = [self colorComponentFrom: colorString start: 0 length: 1];
            green = [self colorComponentFrom: colorString start: 1 length: 1];
            blue  = [self colorComponentFrom: colorString start: 2 length: 1];
            break;
        case 4: // #ARGB
            alpha = [self colorComponentFrom: colorString start: 0 length: 1];
            red   = [self colorComponentFrom: colorString start: 1 length: 1];
            green = [self colorComponentFrom: colorString start: 2 length: 1];
            blue  = [self colorComponentFrom: colorString start: 3 length: 1];          
            break;
        case 6: // #RRGGBB
            alpha = 1.0f;
            red   = [self colorComponentFrom: colorString start: 0 length: 2];
            green = [self colorComponentFrom: colorString start: 2 length: 2];
            blue  = [self colorComponentFrom: colorString start: 4 length: 2];                      
            break;
        case 8: // #AARRGGBB
            alpha = [self colorComponentFrom: colorString start: 0 length: 2];
            red   = [self colorComponentFrom: colorString start: 2 length: 2];
            green = [self colorComponentFrom: colorString start: 4 length: 2];
            blue  = [self colorComponentFrom: colorString start: 6 length: 2];                      
            break;
        default:
            NSLog(@"Error: Invalid color value. It should be a hex value of the form #RBG, #ARGB, #RRGGBB, or #AARRGGBB");
            break;
    }
    return [UIColor colorWithRed: red green: green blue: blue alpha: alpha];
}

- (CGFloat) colorComponentFrom: (NSString *) string start: (NSUInteger) start length: (NSUInteger) length {
    NSString *substring = [string substringWithRange: NSMakeRange(start, length)];
    NSString *fullHex = length == 2 ? substring : [NSString stringWithFormat: @"%@%@", substring, substring];
    unsigned hexComponent;
    [[NSScanner scannerWithString: fullHex] scanHexInt: &hexComponent];
    return hexComponent / 255.0;
}

#pragma mark - URL Methods (not fully implemented YET!)

- (NSString *)getShortURL:(CDVInvokedUrlCommand*)command
{
  Branch *branch = [self getInstance];
  return [branch getShortURL];
}

- (id)getShortURLWithParams:(CDVInvokedUrlCommand*)command
{
  Branch *branch = [self getInstance];
  NSDictionary *params = [command.arguments objectAtIndex:0];

  return [branch getShortURLWithParams:params];
}

- (NSString *)getLongURLWithParams:(CDVInvokedUrlCommand*)command
{
  id params = [command.arguments objectAtIndex:0];
  return [[self getInstance] getLongURLWithParams:params];
}

- (void)getBranchActivityItemWithParams:(CDVInvokedUrlCommand*)command
{
  UIActivityItemProvider *provider = [Branch getBranchActivityItemWithParams:[command.arguments objectAtIndex:0]];

  UIActivityViewController *shareViewController = [[UIActivityViewController alloc] initWithActivityItems:@[ provider ] applicationActivities:nil];

  [self.viewController presentViewController:shareViewController animated:YES completion:nil];
}



@end

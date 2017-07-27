#import "QCVideoSource.h"




@implementation QCVideoSource


/*===================================================================================*/
#pragma mark --------------------- init/dealloc
/*------------------------------------*/


- (id) init	{
	if (self = [super init])	{
		propScene = nil;
		return self;
	}
	[self release];
	return nil;
}
- (void) prepareToBeDeleted	{
	[super prepareToBeDeleted];
}
- (void) dealloc	{
	if (!deleted)
		[self prepareToBeDeleted];
	OSSpinLockLock(&propLock);
	VVRELEASE(propScene);
	OSSpinLockUnlock(&propLock);
	[super dealloc];
}


/*===================================================================================*/
#pragma mark --------------------- superclass overrides
/*------------------------------------*/


- (void) loadFileAtPath:(NSString *)p	{
	NSFileManager	*fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:p])
		return;
	[self stop];
	
	OSSpinLockLock(&propLock);
	VVRELEASE(propPath);
	propPath = [p retain];
	OSSpinLockUnlock(&propLock);
	
	[self start];
}
- (void) _stop	{
	VVRELEASE(propScene);
}
- (VVBuffer *) allocBuffer	{
	VVBuffer		*returnMe = nil;
	OSSpinLockLock(&propLock);
	if (propPath != nil)	{
		VVRELEASE(propScene);
		//propScene = [[QCGLScene alloc] initWithSharedContext:[_globalVVBufferPool sharedContext] sized:NSMakeSize(1280,720)];
		propScene = [[QCGLScene alloc] initCommonBackendSceneSized:NSMakeSize(1280,720)];
		[propScene useFile:propPath];
		VVRELEASE(propPath);
	}
	returnMe = (propScene==nil) ? nil : [propScene allocAndRenderABuffer];
	OSSpinLockUnlock(&propLock);
	return returnMe;
}
- (NSArray *) arrayOfSourceMenuItems	{
	NSMutableArray		*returnMe = MUTARRAY;
	NSArray				*fileNames = @[@"Cube Array", @"Blue"];
	NSBundle			*mb = [NSBundle mainBundle];
	for (NSString *fileName in fileNames)	{
		NSMenuItem		*newItem = [[NSMenuItem alloc] initWithTitle:fileName action:nil keyEquivalent:@""];
		NSString		*filePath = [mb pathForResource:fileName ofType:@"qtz"];
		NSURL			*fileURL = [NSURL fileURLWithPath:filePath];
		[newItem setRepresentedObject:fileURL];
		[returnMe addObject:newItem];
		[newItem release];
	}
	return returnMe;
}


@end

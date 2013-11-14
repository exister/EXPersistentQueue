#import "EXQueue.h"

#define DEFINE_SHARED_INSTANCE_USING_BLOCK(block) \
static dispatch_once_t pred = 0; \
__strong static id _sharedObject = nil; \
dispatch_once(&pred, ^{ \
_sharedObject = block(); \
}); \
return _sharedObject; \

NSString *const EXQueueDidStart = @"EXQueueDidStart";
NSString *const EXQueueDidStop = @"EXQueueDidStop";
NSString *const EXQueueJobDidSucceed = @"EXQueueJobDidSucceed";
NSString *const EXQueueJobDidFailOffline = @"EXQueueJobDidFailOffline";
NSString *const EXQueueJobDidFail = @"EXQueueJobDidFail";
NSString *const EXQueueJobDidFailCritical = @"EXQueueJobDidFailCritical";
NSString *const EXQueueJobDidFailWillRetry = @"EXQueueJobDidFailWillRetry";
NSString *const EXQueueJobDidCancel = @"EXQueueJobDidCancel";
NSString *const EXQueueDidDrain = @"EXQueueDidDrain";

@interface EXQueue ()

@property EXQueueStorageEngine *engine;
@property (atomic, strong) NSString *activeTask;
/**
* Queue has started
*/
@property (atomic) BOOL isRunning;
/**
* One task is currently running
*/
@property (atomic) BOOL isActive;
/**
* Serial task queue
*/
@property (atomic, strong) NSOperationQueue *queue;

/**
 * Checks the queue for available jobs, sends them to the processor delegate, and then handles the response.
 *
 * @return {void}
 */
- (void)tick;

/**
 * Posts a notification (used to keep notifications on the main thread).
 *
 * @param {NSDictionary} Object
 *                          - name: Notification name
 *                          - data: Data to be attached to notification
 *
 * @return {void}
 */
- (void)postNotification:(NSDictionary *)object;

/**
 * Writes an error message to the log.
 *
 * @param {NSString} Message
 *
 * @return {void}
 */
- (void)errorWithMessage:(NSString *)message;
@end


@implementation EXQueue

#pragma mark - Init

+ (EXQueue *)sharedInstance
{
    DEFINE_SHARED_INSTANCE_USING_BLOCK(^{
        return [[self alloc] init];
    });
}

- (id)init
{
    self = [super init];
    if (self) {
        _engine = [[EXQueueStorageEngine alloc] init];
        _isRunning  = NO;
        _isActive   = NO;
        _retryLimit = 4;
        _queue = [[NSOperationQueue alloc] init];
        [_queue setMaxConcurrentOperationCount:1];
    }
    return self;
}

#pragma mark - Public methods

- (void)enqueueWithData:(id)data forTask:(NSString *)task
{
    if (data == nil) {
        data = @{};
    }
    [self.engine createJob:data forTask:task];

    //no other tasks are running
    if (!self.isActive) {
        //operation queue paused or empty
        if (self.queue.isSuspended || self.queue.operationCount == 0) {
            DDLogInfo(@"(%@, %d, %@): empty queue, ticking right away", THIS_FILE, __LINE__, THIS_METHOD);
            [self tick];
        }
    }
}

- (BOOL)jobExistsForTask:(NSString *)task
{
    BOOL jobExists = [self.engine jobExistsForTask:task];
    return jobExists;
}

- (BOOL)jobIsActiveForTask:(NSString *)task
{
    BOOL jobIsActive;
    jobIsActive = [self.activeTask length] > 0 && [self.activeTask isEqualToString:task];
    return jobIsActive;
}

- (NSDictionary *)nextJobForTask:(NSString *)task
{
    NSDictionary *nextJobForTask = [self.engine fetchJobForTask:task];
    return nextJobForTask;
}

- (void)start
{
    if (!self.isRunning) {
        DDLogInfo(@"(%@, %d, %@): Queue started", THIS_FILE, __LINE__, THIS_METHOD);
        self.isRunning = YES;
        [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:BLQueueDidStart, @"name", nil, @"data", nil] waitUntilDone:false];
        [self tick];
    }
}

- (void)stop
{
    if (self.isRunning) {
        DDLogInfo(@"(%@, %d, %@): Queue stopped", THIS_FILE, __LINE__, THIS_METHOD);
        self.isRunning = NO;
        [self.queue setSuspended:YES];
        [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:BLQueueDidStop, @"name", nil, @"data", nil] waitUntilDone:false];
    }
}

- (void)empty
{
    [self.engine removeAllJobs];
}

- (void)filterUsingBlock:(EXFilterResult (^)(NSDictionary *data))filterBlock {
    [self.engine filterQueueUsingBlock:filterBlock];
}

#pragma mark - Private methods

- (void)tick
{
    DDLogInfo(@"(%@, %d, %@): ", THIS_FILE, __LINE__, THIS_METHOD);
    __typeof (&*self) __weak weakSelf = self;

    NSBlockOperation *blockOperation = [[NSBlockOperation alloc] init];
    __weak NSBlockOperation *weakBlockOperation = blockOperation;

    [blockOperation addExecutionBlock:^{
        if (weakBlockOperation.isCancelled) {
            DDLogInfo(@"(%@, %d, %@): This task is canceled", THIS_FILE, __LINE__, THIS_METHOD);
            return;
        }

        __typeof (&*weakSelf) strongSelf = weakSelf;
        DDLogInfo(@"(%@, %d, %@): tickBlockOperation", THIS_FILE, __LINE__, THIS_METHOD);

        BOOL canRun;
        @synchronized (strongSelf) {
            //if queue has been started and there is no other tasks running and there are tasks to run
            canRun = strongSelf.isRunning && !strongSelf.isActive && [strongSelf.engine fetchJobCount] > 0;
        }

        if (canRun) {
            DDLogInfo(@"(%@, %d, %@): Can run", THIS_FILE, __LINE__, THIS_METHOD);
            @synchronized (strongSelf) {
                // Start job
                strongSelf.isActive = YES;
                DDLogInfo(@"(%@, %d, %@): suspending queue", THIS_FILE, __LINE__, THIS_METHOD);
                //because there can be asynchronous tasks, we need to pause operation queue
                [strongSelf.queue setSuspended:YES];
            }
            id job = [strongSelf.engine fetchJob];

            strongSelf.activeTask = [(NSDictionary *)job objectForKey:@"task"];

            DDLogInfo(@"=====================================================");
            DDLogInfo(@"%@", strongSelf.activeTask);
            DDLogInfo(@"=====================================================");

            // asynchronous task
            if ([strongSelf.delegate respondsToSelector:@selector(queue:processJob:completion:)]) {
                [strongSelf.delegate queue:strongSelf processJob:job completion:^(EXQueueResult result) {
                    [strongSelf processJob:job withResult:result];
                    strongSelf.activeTask = nil;
                }];
            }
            // synchronous task
            else {
                EXQueueResult result = [strongSelf.delegate queue:strongSelf processJob:job];
                [strongSelf processJob:job withResult:result];
                strongSelf.activeTask = nil;
            }
        }
        else {
            DDLogInfo(@"(%@, %d, %@): Can't run, suspending queue", THIS_FILE, __LINE__, THIS_METHOD);
            [strongSelf.queue setSuspended:YES];
        }
    }];

    [self.queue addOperation:blockOperation];
    [self.queue setSuspended:NO];
}

- (void)processJob:(NSDictionary*)job withResult:(EXQueueResult)result
{
    DDLogInfo(@"(%@, %d, %@): ", THIS_FILE, __LINE__, THIS_METHOD);

    // Check result
    switch (result) {
        //send successful notification and remove job from queue
        case EXQueueResultSuccess:
            [self performSelectorOnMainThread:@selector(postNotification:)
                                   withObject:@{
                                           @"name": EXQueueJobDidSucceed,
                                           @"data": job
                                   }
                                waitUntilDone:false];
            [self.engine removeJob:job[@"id"]];
            break;

        //send offline notification and keep job in queue
        case EXQueueResultOffline:
            [self performSelectorOnMainThread:@selector(postNotification:)
                                   withObject:@{
                                           @"name": EXQueueJobDidFailOffline,
                                           @"data": job
                                   }
                                waitUntilDone:true];
            break;

        //send will retry notification, increment attempts counter, keep job in queue
        //or send fail notification and delete job from queue
        case EXQueueResultFail:
            NSUInteger currentAttempt = (NSUInteger) ([job[@"attempts"] intValue] + 1);

            if (currentAttempt < self.retryLimit) {
                [self performSelectorOnMainThread:@selector(postNotification:)
                                       withObject:@{
                                               @"name": EXQueueJobDidFailWillRetry,
                                               @"data": job
                                       }
                                    waitUntilDone:true];
                [self.engine incrementAttemptForJob:job[@"id"]];
            }
            else {
                [self performSelectorOnMainThread:@selector(postNotification:)
                                       withObject:@{
                                               @"name": EXQueueJobDidFail,
                                               @"data": job
                                       }
                                    waitUntilDone:true];
                [self.engine removeJob:job[@"id"]];
            }
            break;

        //don't send any notifications, remove job from queue
        case EXQueueResultRemoveSilently:
            [self errorWithMessage:@"Removing job silenty."];
            [self.engine removeJob:job[@"id"]];
            break;

        //send critical error notification, remove job from queue
        case EXQueueResultCritical:
            [self performSelectorOnMainThread:@selector(postNotification:)
                                   withObject:@{
                                           @"name": EXQueueJobDidFailCritical,
                                           @"data": job
                                   }
                                waitUntilDone:false];
            [self errorWithMessage:@"Critical error. Job canceled."];
            [self.engine removeJob:job[@"id"]];
            break;

        //send canceled notification, remove job from queue
        case EXQueueResultCancel:
            [self performSelectorOnMainThread:@selector(postNotification:)
                                   withObject:@{
                                           @"name": EXQueueJobDidCancel,
                                           @"data": job
                                   }
                                waitUntilDone:false];
            [self errorWithMessage:@"Manual cancel. Job canceled."];
            [self.engine removeJob:job[@"id"]];
            break;

        default:
            break;
    }

    @synchronized (self) {
        // Clean-up
        self.isActive = NO;
    }

    // Drain
    if ([self.engine fetchJobCount] == 0) {
        DDLogInfo(@"(%@, %d, %@): No more tasks", THIS_FILE, __LINE__, THIS_METHOD);
        [self.queue cancelAllOperations];
        //TODO data nil
        [self performSelectorOnMainThread:@selector(postNotification:)
                               withObject:@{
                                       @"name": EXQueueDidDrain,
                                       @"data": nil
                               }
                            waitUntilDone:false];
    }
    else {
        DDLogInfo(@"(%@, %d, %@): Queue is empty, running tick, after job ended", THIS_FILE, __LINE__, THIS_METHOD);
        [self performSelectorOnMainThread:@selector(tick) withObject:nil waitUntilDone:false];
    }
}


- (void)postNotification:(NSDictionary *)object
{
    [[NSNotificationCenter defaultCenter] postNotificationName:[object objectForKey:@"name"] object:nil userInfo:[object objectForKey:@"data"]];
}

- (void)errorWithMessage:(NSString *)message
{
    DDLogError(@"(%@, %d, %@): EXQueue Error %@", THIS_FILE, __LINE__, THIS_METHOD, message);
}

- (BOOL)isIdle {
    return !self.isActive && [self.engine fetchJobCount] == 0;
}

#pragma mark - Dealloc

- (void)dealloc
{    
    self.delegate = nil;
    _engine = nil;
    _queue = nil;
}

@end

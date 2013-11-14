#import <Foundation/Foundation.h>

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMDatabasePool.h"
#import "FMDatabaseQueue.h"

typedef enum {
    EXFilterResultAttemptToDelete = 0,
    EXFilterResultNoChange
} EXFilterResult;

@interface EXQueueStorageEngine : NSObject

@property (retain) FMDatabaseQueue *queue;

- (void)createJob:(id)data forTask:(id)task;
- (BOOL)jobExistsForTask:(id)task;
- (void)incrementAttemptForJob:(NSNumber *)jid;
- (void)removeJob:(NSNumber *)jid;
- (void)removeAllJobs;
- (NSUInteger)fetchJobCount;
- (NSDictionary *)fetchJob;
- (NSDictionary *)fetchJobForTask:(id)task;

- (void)filterQueueUsingBlock:(EXFilterResult (^)(NSDictionary *data))filterBlock;
@end
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "EXQueueStorageEngine.h"

typedef enum {
    EXQueueResultSuccess,
    EXQueueResultOffline,
    EXQueueResultFail,
    EXQueueResultCritical,
    EXQueueResultRemoveSilently,
    EXQueueResultCancel,
} EXQueueResult;

UIKIT_EXTERN NSString *const EXQueueDidStart;
UIKIT_EXTERN NSString *const EXQueueDidStop;
UIKIT_EXTERN NSString *const EXQueueJobDidSucceed;
UIKIT_EXTERN NSString *const EXQueueJobDidFailOffline;
UIKIT_EXTERN NSString *const EXQueueJobDidFail;
UIKIT_EXTERN NSString *const EXQueueJobDidFailCritical;
UIKIT_EXTERN NSString *const EXQueueJobDidFailWillRetry;
UIKIT_EXTERN NSString *const EXQueueJobDidCancel;
UIKIT_EXTERN NSString *const EXQueueDidDrain;


@class EXQueue;


@protocol BLQueueDelegate <NSObject>
@optional
- (EXQueueResult)queue:(EXQueue *)queue processJob:(NSDictionary *)job;
- (void)queue:(EXQueue *)queue processJob:(NSDictionary *)job completion:(void (^)(EXQueueResult result))block;
@end


@interface EXQueue : NSObject

@property (weak) id<BLQueueDelegate> delegate;
@property NSUInteger retryLimit;

+ (EXQueue *)sharedInstance;

/**
 * Adds a new job to the queue.
 *
 * @param {id} Data
 * @param {NSString} Task label
 *
 * @return {void}
 */
- (void)enqueueWithData:(id)data forTask:(NSString *)task;

/**
 * Starts the queue.
 *
 * @return {void}
 */
- (void)start;

/**
 * Stops the queue.
 * @note Jobs that have already started will continue to process even after stop has been called.
 *
 * @return {void}
 */
- (void)stop;

/**
 * Empties the queue.
 * @note Jobs that have already started will continue to process even after empty has been called.
 *
 * @return {void}
 */
- (void)empty;

- (void)filterUsingBlock:(EXFilterResult (^)(NSDictionary *data))filterBlock;

/**
* Has currently running job
*/
- (BOOL)isIdle;

/**
 * Returns true if a job exists for this task.
 *
 * @param {NSString} Task label
 *
 * @return {BOOL}
 */
- (BOOL)jobExistsForTask:(NSString *)task;

/**
 * Returns true if the active job if for this task.
 *
 * @param {NSString} Task label
 *
 * @return {BOOL}
 */
- (BOOL)jobIsActiveForTask:(NSString *)task;

/**
 * Returns the list of jobs for this
 *
 * @param {NSString} Task label
 *
 * @return {NSArray}
 */
- (NSDictionary *)nextJobForTask:(NSString *)task;

@end
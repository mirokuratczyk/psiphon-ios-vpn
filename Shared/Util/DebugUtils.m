/*
 * Copyright (c) 2018, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "DebugUtils.h"
#import "AppStats.h"
#import "Asserts.h"
#import "Logging.h"
#import "AppProfiler.h"

@implementation DebugUtils

+ (dispatch_source_t)jetsamWithAllocationInterval:(NSTimeInterval)allocationInterval withNumberOfPages:(unsigned int)pageNum {

    [AppProfiler logMemoryReportWithTag:@"jetsam initiated"];

    NSError *err;
    vm_size_t pageSize = [AppStats pageSize:&err];
    if (err != nil) {
        LOG_DEBUG(@"Failed to get page size: %@", err);
        PSIAssert(FALSE);
    }

    dispatch_source_t timerDispatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                           dispatch_get_main_queue());

    dispatch_source_set_timer(timerDispatch,
                              dispatch_time(DISPATCH_TIME_NOW, allocationInterval * NSEC_PER_SEC),
                              allocationInterval * NSEC_PER_SEC,
                              1 * NSEC_PER_SEC);

    dispatch_source_set_event_handler(timerDispatch, ^{
        [AppProfiler logMemoryReportWithTag:@"jetsam"];
        char * array = (char *) malloc(sizeof(char) * pageSize * pageNum);
        for (int i = 1; i <= pageNum; i++) {
            array[i * pageSize - 1] = '0';
        }
    });

    dispatch_resume(timerDispatch);

    return timerDispatch;
}

@end

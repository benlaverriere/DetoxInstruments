//
//  Swiftier.h
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 11/22/17.
//  Copyright © 2017-2019 Wix. All rights reserved.
//

#ifndef Swiftier_h
#define Swiftier_h

#ifndef DTX_NOTHROW
#define DTX_NOTHROW __attribute__((__nothrow__))
#endif
#ifndef DTX_ALWAYS_INLINE
#define DTX_ALWAYS_INLINE inline __attribute__((__always_inline__))
#endif
#ifndef DTX_WARN_UNUSED_RESULT
#define DTX_WARN_UNUSED_RESULT __attribute__((__warn_unused_result__))
#endif

#if ! defined(__cplusplus)
#import <stdatomic.h>

#if ! defined(thread_local)
#define thread_local _Thread_local
#endif

#if ! defined(__cplusplus) && ! defined(auto)
#define auto __auto_type
#endif
#endif

typedef _Atomic(void*) atomic_voidptr;
typedef _Atomic(const void*) atomic_constvoidptr;
typedef _Atomic(double) atomic_double;

#if __has_include(<mach/mach_types.h>)
#import <mach/mach_types.h>
typedef _Atomic(thread_t) atomic_thread;
#endif

#define dtx_defer_block_name_with_prefix(prefix, suffix) prefix ## suffix
#define dtx_defer_block_name(suffix) dtx_defer_block_name_with_prefix(defer_, suffix)
#define dtx_defer __strong void(^dtx_defer_block_name(__LINE__))(void) __attribute__((cleanup(defer_cleanup_block), unused)) = ^
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
static void defer_cleanup_block(__strong void(^*block)(void)) {
	(*block)();
}
#pragma clang diagnostic pop

#ifdef __OBJC__
#define NS(x) ((__bridge id)x)
#define CF(x) ((__bridge CFTypeRef)x)
#define PTR(x) ((__bridge void*)x)

#define unavailable(...) @available(__VA_ARGS__)) { } else if(YES

#if ! defined(__cplusplus)
#ifndef swap
#define swap(x, y) do { typeof(x) t = x; x = y; y = t; }while(0)
#endif
#endif

#ifdef __cplusplus
#import <Foundation/Foundation.h>
#else
@import Foundation;
#endif

@interface NSArray <ElementType> (PSPDFSafeCopy)
- (NSArray <ElementType> *)copy;
- (NSMutableArray <ElementType> *)mutableCopy;
@end

@interface NSSet <ElementType> (PSPDFSafeCopy)
- (NSSet <ElementType> *)copy;
- (NSMutableSet <ElementType> *)mutableCopy;
@end

@interface NSDictionary <KeyType, ValueType> (PSPDFSafeCopy)
- (NSDictionary <KeyType, ValueType> *)copy;
- (NSMutableDictionary <KeyType, ValueType> *)mutableCopy;
@end

@interface NSOrderedSet <ElementType> (PSPDFSafeCopy)
- (NSOrderedSet <ElementType> *)copy;
- (NSMutableOrderedSet <ElementType> *)mutableCopy;
@end

@interface NSHashTable <ElementType> (PSPDFSafeCopy)
- (NSHashTable <ElementType> *)copy;
@end

@interface NSMapTable <KeyType, ValueType> (PSPDFSafeCopy)
- (NSMapTable <KeyType, ValueType> *)copy;
@end

#endif

#define CLANG_IGNORE_HELPER0(x) #x
#define CLANG_IGNORE_HELPER1(x) CLANG_IGNORE_HELPER0(clang diagnostic ignored x)
#define CLANG_IGNORE_HELPER2(y) CLANG_IGNORE_HELPER1(#y)
#define CLANG_POP _Pragma("clang diagnostic pop")
#define CLANG_IGNORE(x)\
    _Pragma("clang diagnostic push");\
    _Pragma(CLANG_IGNORE_HELPER2(x))

#define pthread_mutex_lock_deferred_unlock(mutex) \
pthread_mutex_lock(mutex);\
dtx_defer {\
	pthread_mutex_unlock(mutex);\
};

#endif /* Swiftier_pch */

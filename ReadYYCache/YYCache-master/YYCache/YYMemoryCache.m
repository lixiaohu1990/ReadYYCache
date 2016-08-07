//
//  YYMemoryCache.m
//  YYCache <https://github.com/ibireme/YYCache>
//
//  Created by ibireme on 15/2/7.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "YYMemoryCache.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>


static inline dispatch_queue_t YYMemoryCacheGetReleaseQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
}

/**
 A node in linked map.
 Typically, you should not use this class directly.
 */

//链表节点
@interface _YYLinkedMapNode : NSObject {
    @package
    
//    因为每个node都会被CFDictionary进行retain操作，所以这里使用的是__unsafe_unretained
    
//指向前一个节点
    __unsafe_unretained _YYLinkedMapNode *_prev; // retained by dic
//指向后一个节点
    __unsafe_unretained _YYLinkedMapNode *_next; // retained by dic
//缓存key
    id _key;
//缓存对象
    id _value;
//当前缓存开销
    NSUInteger _cost;
//缓存时间
    NSTimeInterval _time;
    
//    通过以上6个成员变量，就能完成时间，空间，数量的淘汰算法
}
@end

@implementation _YYLinkedMapNode
@end


/**
 A linked map used by YYMemoryCache.
 It's not thread-safe and does not validate the parameters.
 
 Typically, you should not use this class directly.
 */

//链表
@interface _YYLinkedMap : NSObject {
//    @package是为了不让framework外部对其进行操作
    @package
// 用字典保存所有节点_YYLinkedMapNode (为什么不用oc字典?因为用CFMutableDictionaryRef效率高，毕竟基于c)
    CFMutableDictionaryRef _dic; // do not set object directly
//    总缓存开销
    NSUInteger _totalCost;
//    总缓存数量
    NSUInteger _totalCount;
//    链表头节点
    _YYLinkedMapNode *_head; // MRU, do not change it directly
//    链表尾节点
    _YYLinkedMapNode *_tail; // LRU, do not change it directly
    // 是否在主线程上，异步释放 _YYLinkedMapNode对象
    BOOL _releaseOnMainThread;
    // 是否异步释放 _YYLinkedMapNode对象
    BOOL _releaseAsynchronously;
}

/// Insert a node at head and update the total cost.
/// Node and node.key should not be nil.
// 添加节点到链表头节点
- (void)insertNodeAtHead:(_YYLinkedMapNode *)node;

/// Bring a inner node to header.
/// Node should already inside the dic.
// 移动当前节点到链表头节点
- (void)bringNodeToHead:(_YYLinkedMapNode *)node;

/// Remove a inner node and update the total cost.
/// Node should already inside the dic.
// 移除链表节点
- (void)removeNode:(_YYLinkedMapNode *)node;

/// Remove tail node if exist.
// 移除链表尾节点(如果存在)
- (_YYLinkedMapNode *)removeTailNode;

/// Remove all node in background queue.
// 移除所有缓存
- (void)removeAll;

@end


@implementation _YYLinkedMap

- (instancetype)init {
    self = [super init];
    _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    _releaseOnMainThread = NO;
    _releaseAsynchronously = YES;
    return self;
}

- (void)dealloc {
    CFRelease(_dic);
}

//方法插入、替换、查找方法实现

// 添加节点到链表头节点
- (void)insertNodeAtHead:(_YYLinkedMapNode *)node {
    // 字典保存链表节点node
    CFDictionarySetValue(_dic, (__bridge const void *)(node->_key), (__bridge const void *)(node));
    // 叠加该缓存开销到总内存开销
    _totalCost += node->_cost;
    // 总缓存数+1
    _totalCount++;
    if (_head) {
        // 存在链表头，取代当前表头
        node->_next = _head;
        _head->_prev = node;
        // 重新赋值链表表头临时变量_head
        _head = node;
    } else {
        // 不存在链表头
        _head = _tail = node;
    }
}

// 移动当前节点到链表头节点
- (void)bringNodeToHead:(_YYLinkedMapNode *)node {
    
    // 当前节点已是链表头节点
    if (_head == node) return;
    
    if (_tail == node) {
        //**如果node是链表尾节点**
        
        // 把node指向的上一个节点赋值给链表尾节点
        _tail = node->_prev;
        // 把链表尾节点指向的下一个节点赋值nil
        _tail->_next = nil;
    } else {
        //**如果node是非链表尾节点和链表头节点**
        
        // 把node指向的上一个节点赋值給node指向的下一个节点node指向的上一个节点
        node->_next->_prev = node->_prev;
        // 把node指向的下一个节点赋值给node指向的上一个节点node指向的下一个节点
        node->_prev->_next = node->_next;
    }
    // 把链表头节点赋值给node指向的下一个节点
    node->_next = _head;
    // 把node指向的上一个节点赋值nil
    node->_prev = nil;
    // 把节点赋值给链表头节点的指向的上一个节点
    _head->_prev = node;
    _head = node;
}

// 移除节点
- (void)removeNode:(_YYLinkedMapNode *)node {
    // 从字典中移除node
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(node->_key));
    // 减掉总内存消耗
    _totalCost -= node->_cost;
    // // 总缓存数-1
    _totalCount--;
    
    // 重新连接链表
    if (node->_next) node->_next->_prev = node->_prev;
    if (node->_prev) node->_prev->_next = node->_next;
    if (_head == node) _head = node->_next;
    if (_tail == node) _tail = node->_prev;
}
// 移除尾节点(如果存在)
- (_YYLinkedMapNode *)removeTailNode {
    if (!_tail) return nil;
    // 拷贝一份要删除的尾节点指针
    _YYLinkedMapNode *tail = _tail;
    // 移除链表尾节点
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(_tail->_key));
    // 减掉总内存消耗
    _totalCost -= _tail->_cost;
    // 总缓存数-1
    _totalCount--;
    if (_head == _tail) {
        // 清除节点，链表上已无节点了
        _head = _tail = nil;
    } else {
        // 设倒数第二个节点为链表尾节点
        _tail = _tail->_prev;
        _tail->_next = nil;
    }
    // 返回完tail后_tail将会释放
    return tail;
}

// 移除所有缓存
- (void)removeAll {
    // 清空内存开销与缓存数量
    _totalCost = 0;
    _totalCount = 0;
    // 清空头尾节点
    _head = nil;
    _tail = nil;
    
    if (CFDictionaryGetCount(_dic) > 0) {
        // 拷贝一份字典
        CFMutableDictionaryRef holder = _dic;
        // 重新分配新的空间
        _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        if (_releaseAsynchronously) {
            // 异步释放缓存
            dispatch_queue_t queue = _releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                CFRelease(holder); // hold and release in specified queue
            });
        } else if (_releaseOnMainThread && !pthread_main_np()) {
            // 主线程上释放缓存
            dispatch_async(dispatch_get_main_queue(), ^{
                CFRelease(holder); // hold and release in specified queue
            });
        } else {
            // 同步释放缓存
            CFRelease(holder);
        }
    }
}

@end



@implementation YYMemoryCache {
    pthread_mutex_t _lock;
    _YYLinkedMap *_lru;
    dispatch_queue_t _queue;
}

//当我们初始化一个MemoryCache实例之后，这个实例就会自创建成功后递归调用- (void)_trimRecursively
//利用dispatch_after根据外部设置的_autoTrimInterval（默认5s）进行递归操作。分别轮询costLimit，countLimit以及ageLimit
- (void)_trimRecursively {
    __weak typeof(self) _self = self;
//    这个递归是通过GCD的dispatchAfter来实现的，并且是在非主队列中进行递归，因此在不断递归检测是否超过所设置的countLimit和其他限制，然后判断是否进行缓存淘汰处理
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        [self _trimInBackground];
        [self _trimRecursively];
    });
}

- (void)_trimInBackground {
    dispatch_async(_queue, ^{
        [self _trimToCost:self->_costLimit];
        [self _trimToCount:self->_countLimit];
        [self _trimToAge:self->_ageLimit];
    });
}

- (void)_trimToCost:(NSUInteger)costLimit {
    BOOL finish = NO;
    pthread_mutex_lock(&_lock);
    if (costLimit == 0) {
//       首先判断外部设置的costLimit是否为0，是则将MemoryCache全部清除
        [_lru removeAll];
        finish = YES;
    } else if (_lru->_totalCost <= costLimit) {
        finish = YES;
    }
    pthread_mutex_unlock(&_lock);
    if (finish) return;
    
//    判断costCount是否大于costLimit，若大于，则尝试加锁进行尾部节点的移除
//    为了避免多次释放导致的性能开销，这里是将所有的尾节点放于一个数组中，集中释放。
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (pthread_mutex_trylock(&_lock) == 0) {
            if (_lru->_totalCost > costLimit) {
                _YYLinkedMapNode *node = [_lru removeTailNode];
                if (node) [holder addObject:node];
            } else {
                finish = YES;
            }
            pthread_mutex_unlock(&_lock);
        } else {
            usleep(10 * 1000); //10 ms
        }
    }
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count]; // release in queue
//            block对holder引用，为了hold住holder, 让holder在指定的NSThread释放, 调用对象方法count并没干什么事
        });
    }
}

- (void)_trimToCount:(NSUInteger)countLimit {
    BOOL finish = NO;
    pthread_mutex_lock(&_lock);
    if (countLimit == 0) {
        [_lru removeAll];
        finish = YES;
    } else if (_lru->_totalCount <= countLimit) {
        finish = YES;
    }
    pthread_mutex_unlock(&_lock);
    if (finish) return;
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (pthread_mutex_trylock(&_lock) == 0) {
            if (_lru->_totalCount > countLimit) {
                _YYLinkedMapNode *node = [_lru removeTailNode];
                if (node) [holder addObject:node];
            } else {
                finish = YES;
            }
            pthread_mutex_unlock(&_lock);
        } else {
            usleep(10 * 1000); //10 ms
        }
    }
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count]; // release in queue
        });
    }
}

- (void)_trimToAge:(NSTimeInterval)ageLimit {
    BOOL finish = NO;
    NSTimeInterval now = CACurrentMediaTime();
    pthread_mutex_lock(&_lock);
    if (ageLimit <= 0) {
        [_lru removeAll];
        finish = YES;
    } else if (!_lru->_tail || (now - _lru->_tail->_time) <= ageLimit) {
        finish = YES;
    }
    pthread_mutex_unlock(&_lock);
    if (finish) return;
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (pthread_mutex_trylock(&_lock) == 0) {
            if (_lru->_tail && (now - _lru->_tail->_time) > ageLimit) {
                _YYLinkedMapNode *node = [_lru removeTailNode];
                if (node) [holder addObject:node];
            } else {
                finish = YES;
            }
            pthread_mutex_unlock(&_lock);
        } else {
            usleep(10 * 1000); //10 ms
        }
    }
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count]; // release in queue
        });
    }
}

- (void)_appDidReceiveMemoryWarningNotification {
    if (self.didReceiveMemoryWarningBlock) {
        self.didReceiveMemoryWarningBlock(self);
    }
    if (self.shouldRemoveAllObjectsOnMemoryWarning) {
        [self removeAllObjects];
    }
}

- (void)_appDidEnterBackgroundNotification {
    if (self.didEnterBackgroundBlock) {
        self.didEnterBackgroundBlock(self);
    }
    if (self.shouldRemoveAllObjectsWhenEnteringBackground) {
        [self removeAllObjects];
    }
}

#pragma mark - public

- (instancetype)init {
    self = super.init;
    pthread_mutex_init(&_lock, NULL);
    _lru = [_YYLinkedMap new];
    _queue = dispatch_queue_create("com.ibireme.cache.memory", DISPATCH_QUEUE_SERIAL);
    
    _countLimit = NSUIntegerMax;
    _costLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _autoTrimInterval = 5.0;
    _shouldRemoveAllObjectsOnMemoryWarning = YES;
    _shouldRemoveAllObjectsWhenEnteringBackground = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidReceiveMemoryWarningNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidEnterBackgroundNotification) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    [self _trimRecursively];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [_lru removeAll];
    pthread_mutex_destroy(&_lock);
}

- (NSUInteger)totalCount {
    pthread_mutex_lock(&_lock);
    NSUInteger count = _lru->_totalCount;
    pthread_mutex_unlock(&_lock);
    return count;
}

- (NSUInteger)totalCost {
    pthread_mutex_lock(&_lock);
    NSUInteger totalCost = _lru->_totalCost;
    pthread_mutex_unlock(&_lock);
    return totalCost;
}

- (BOOL)releaseOnMainThread {
    pthread_mutex_lock(&_lock);
    BOOL releaseOnMainThread = _lru->_releaseOnMainThread;
    pthread_mutex_unlock(&_lock);
    return releaseOnMainThread;
}

- (void)setReleaseOnMainThread:(BOOL)releaseOnMainThread {
    pthread_mutex_lock(&_lock);
    _lru->_releaseOnMainThread = releaseOnMainThread;
    pthread_mutex_unlock(&_lock);
}

- (BOOL)releaseAsynchronously {
    pthread_mutex_lock(&_lock);
    BOOL releaseAsynchronously = _lru->_releaseAsynchronously;
    pthread_mutex_unlock(&_lock);
    return releaseAsynchronously;
}

- (void)setReleaseAsynchronously:(BOOL)releaseAsynchronously {
    pthread_mutex_lock(&_lock);
    _lru->_releaseAsynchronously = releaseAsynchronously;
    pthread_mutex_unlock(&_lock);
}

- (BOOL)containsObjectForKey:(id)key {
    if (!key) return NO;
    pthread_mutex_lock(&_lock);
    BOOL contains = CFDictionaryContainsKey(_lru->_dic, (__bridge const void *)(key));
    pthread_mutex_unlock(&_lock);
    return contains;
}
// 查找缓存
- (id)objectForKey:(id)key {
    if (!key) return nil;
    // 加锁，防止资源竞争
    // OSSpinLock 自旋锁，性能最高的锁。原理很简单，就是一直 do while 忙等。它的缺点是当等待时会消耗大量 CPU 资源，所以它不适用于较长时间的任务。对于内存缓存的存取来说，它非常合适。
    pthread_mutex_lock(&_lock);
    // _lru为链表_YYLinkedMap，全部节点存在_lru->_dic中
    // 获取节点
    _YYLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    if (node) {
        
        //** 有对应缓存 **
        
        // 重新更新缓存时间
        
        node->_time = CACurrentMediaTime();
        // 把当前node移到链表表头(为什么移到表头？根据LRU淘汰算法:Cache的容量是有限的，当Cache的空间都被占满后，如果再次发生缓存失效，就必须选择一个缓存块来替换掉.LRU法是依据各块使用的情况， 总是选择那个最长时间未被使用的块替换。这种方法比较好地反映了程序局部性规律)
        
    
        [_lru bringNodeToHead:node];
    }
    // 解锁
    pthread_mutex_unlock(&_lock);
    // 有缓存则返回缓存值
    return node ? node->_value : nil;
}

- (void)setObject:(id)object forKey:(id)key {
    [self setObject:object forKey:key withCost:0];
}
//添加缓存
- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost {
    if (!key) return;
    if (!object) {
        // ** 缓存对象为空，移除缓存
//        当object不存在时，调用removeObjectForKey 进行删除
//        **
        [self removeObjectForKey:key];
        return;
    }
//    加锁
    pthread_mutex_lock(&_lock);
//    查找缓存
    _YYLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
//    当前时间
    NSTimeInterval now = CACurrentMediaTime();
    if (node) {
        //** 之前有缓存，更新旧缓存 **
        
        // 更新值
        _lru->_totalCost -= node->_cost;
        _lru->_totalCost += cost;
        node->_cost = cost;
        node->_time = now;
        node->_value = object;
        // 移动节点到链表表头
        [_lru bringNodeToHead:node];
    } else {
        
        //** 之前未有缓存，添加新缓存 **
        
        // 新建节点
        
//        创建一个新的node，然后通过->来对成员变量进行赋值（不用点语法就是为了节省调用方法的时间，提升性能，还有OC中对象进行 ->是访问成员变量，由于之前采用了 @package操作，所以不能在外部通过->来访问成员变量，和结构体的->类似）
        
        node = [_YYLinkedMapNode new];
        node->_cost = cost;
        node->_time = now;
        node->_key = key;
        node->_value = object;
        
        // 添加节点到表头
//        用_lru(_YYLinkedMap的实例)将node插入到链表头部
        [_lru insertNodeAtHead:node];
    }
    
//    检查是否超过数量和大小的限制，以进行尾部的node删除，然后在后台线程释放
    if (_lru->_totalCost > _costLimit) {
        
        // ** 总缓存开销大于设定的开销 **
        
        // 异步清理最久未使用的缓存
        dispatch_async(_queue, ^{
            [self trimToCost:_costLimit];
        });
    }
    if (_lru->_totalCount > _countLimit) {
        _YYLinkedMapNode *node = [_lru removeTailNode];
        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class]; //hold and release in queue
            });
        } else if (_lru->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class]; //hold and release in queue
                
//                这里是为了给node增加使用的周期，如果没有在开的queue中调用node的方法，node就会在queue之前被释放掉 这样做的目的是为了让node在开的子线程中进行释放而不是在主线程
            });
        }
    }
    pthread_mutex_unlock(&_lock);
}

- (void)removeObjectForKey:(id)key {
    if (!key) return;
    pthread_mutex_lock(&_lock);
    _YYLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    if (node) {
        [_lru removeNode:node];
        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class]; //hold and release in queue
            });
        } else if (_lru->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class]; //hold and release in queue
            });
        }
    }
    pthread_mutex_unlock(&_lock);
}

- (void)removeAllObjects {
    pthread_mutex_lock(&_lock);
    [_lru removeAll];
    pthread_mutex_unlock(&_lock);
}

- (void)trimToCount:(NSUInteger)count {
    if (count == 0) {
        [self removeAllObjects];
        return;
    }
    [self _trimToCount:count];
}

- (void)trimToCost:(NSUInteger)cost {
    [self _trimToCost:cost];
}

- (void)trimToAge:(NSTimeInterval)age {
    [self _trimToAge:age];
}

- (NSString *)description {
    if (_name) return [NSString stringWithFormat:@"<%@: %p> (%@)", self.class, self, _name];
    else return [NSString stringWithFormat:@"<%@: %p>", self.class, self];
}

@end

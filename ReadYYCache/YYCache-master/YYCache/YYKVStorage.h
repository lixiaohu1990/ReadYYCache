//
//  YYKVStorage.h
//  YYCache <https://github.com/ibireme/YYCache>
//
//  Created by ibireme on 15/4/22.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 YYKVStorageItem is used by `YYKVStorage` to store key-value pair and meta data.
 Typically, you should not use this class directly.
 */


// 用item封装缓存数据的参数
@interface YYKVStorageItem : NSObject
// 用YYKVStorageItem保存缓存相关参数

//缓存键值
@property (nonatomic, strong) NSString *key;                ///< key
//缓存对象
@property (nonatomic, strong) NSData *value;                ///< value
//缓存文件名
@property (nullable, nonatomic, strong) NSString *filename; ///< filename (nil if inline)
//缓存大小
@property (nonatomic) int size;                             ///< value's size in bytes
//修改时间
@property (nonatomic) int modTime;                          ///< modification unix timestamp
//最后使用时间
@property (nonatomic) int accessTime;                       ///< last access unix timestamp
//拓展数据
@property (nullable, nonatomic, strong) NSData *extendedData; ///< extended data (nil if no extended data)
@end

/**
 Storage type, indicated where the `YYKVStorageItem.value` stored.
 
 @discussion Typically, write data to sqlite is faster than extern file, but 
 reading performance is dependent on data size. In my test (on iPhone 6 64G), 
 read data from extern file is faster than from sqlite when the data is larger 
 than 20KB.
 
 * If you want to store large number of small datas (such as contacts cache), 
   use YYKVStorageTypeSQLite to get better performance.
 * If you want to store large files (such as image cache),
   use YYKVStorageTypeFile to get better performance.
 * You can use YYKVStorageTypeMixed and choice your storage type for each item.
 
 See <http://www.sqlite.org/intern-v-extern-blob.html> for more information.
 */

//可以指定缓存类型
typedef NS_ENUM(NSUInteger, YYKVStorageType) {
    // 文件缓存(filename != null)
    /// The `value` is stored as a file in file system.
    YYKVStorageTypeFile = 0,
    // 数据库缓存
    /// The `value` is stored in sqlite with blob type.
    YYKVStorageTypeSQLite = 1,
    // 如果filename != null，则value用文件缓存，缓存的其他参数用数据库缓存；如果filename == null,则用数据库缓存
    /// The `value` is stored in file system or sqlite based on your choice.
    YYKVStorageTypeMixed = 2,
};



/**
 YYKVStorage is a key-value storage based on sqlite and file system.
 Typically, you should not use this class directly.
 
 @discussion The designated initializer for YYKVStorage is `initWithPath:type:`. 
 After initialized, a directory is created based on the `path` to hold key-value data.
 Once initialized you should not read or write this directory without the instance.
 
 You may compile the latest version of sqlite and ignore the libsqlite3.dylib in
 iOS system to get 2x~4x speed up.
 
 @warning The instance of this class is *NOT* thread safe, you need to make sure 
 that there's only one thread to access the instance at the same time. If you really 
 need to process large amounts of data in multi-thread, you should split the data
 to multiple KVStorage instance (sharding).
 */

//缓存操作实现
@interface YYKVStorage : NSObject


#pragma mark - Attribute
///=============================================================================
/// @name Attribute
///=============================================================================
//属性参数

//缓存路径
@property (nonatomic, readonly) NSString *path;        ///< The path of this storage.
//缓存方式
@property (nonatomic, readonly) YYKVStorageType type;  ///< The type of this storage.
//是否要打开错误日志
@property (nonatomic) BOOL errorLogsEnabled;           ///< Set `YES` to enable error logs for debug.

//初始化方法
#pragma mark - Initializer
///=============================================================================
/// @name Initializer
///=============================================================================
// 这两个方法不能使用，因为实例化对象时要有初始化path、type
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;

/**
 The designated initializer. 
 
 @param path  Full path of a directory in which the storage will write data. If
    the directory is not exists, it will try to create one, otherwise it will 
    read the data in this directory.
 @param type  The storage type. After first initialized you should not change the 
    type of the specified path.
 @return  A new storage object, or nil if an error occurs.
 @warning Multiple instances with the same path will make the storage unstable.
 */

/**
 *  实例化对象
 *
 *  @param path 缓存路径
 *  @param type 缓存方式
 */

- (nullable instancetype)initWithPath:(NSString *)path type:(YYKVStorageType)type NS_DESIGNATED_INITIALIZER;


#pragma mark - Save Items
///=============================================================================
/// @name Save Items
///=============================================================================

/**
 Save an item or update the item with 'key' if it already exists.
 
 @discussion This method will save the item.key, item.value, item.filename and
 item.extendedData to disk or sqlite, other properties will be ignored. item.key 
 and item.value should not be empty (nil or zero length).
 
 If the `type` is YYKVStorageTypeFile, then the item.filename should not be empty.
 If the `type` is YYKVStorageTypeSQLite, then the item.filename will be ignored.
 It the `type` is YYKVStorageTypeMixed, then the item.value will be saved to file 
 system if the item.filename is not empty, otherwise it will be saved to sqlite.
 
 @param item  An item.
 @return Whether succeed.
 */


//添加缓存

/**
 *  添加缓存
 *
 *  @param item 把缓存数据封装到YYKVStorageItem对象
 */

- (BOOL)saveItem:(YYKVStorageItem *)item;

/**
 Save an item or update the item with 'key' if it already exists.
 
 @discussion This method will save the key-value pair to sqlite. If the `type` is
 YYKVStorageTypeFile, then this method will failed.
 
 @param key   The key, should not be empty (nil or zero length).
 @param value The key, should not be empty (nil or zero length).
 @return Whether succeed.
 */

/**
 *  添加缓存
 *
 *  @param key   缓存键值
 *  @param value 缓存对象
 */

- (BOOL)saveItemWithKey:(NSString *)key value:(NSData *)value;

/**
 Save an item or update the item with 'key' if it already exists.
 
 @discussion
 If the `type` is YYKVStorageTypeFile, then the `filename` should not be empty.
 If the `type` is YYKVStorageTypeSQLite, then the `filename` will be ignored.
 It the `type` is YYKVStorageTypeMixed, then the `value` will be saved to file
 system if the `filename` is not empty, otherwise it will be saved to sqlite.
 
 @param key           The key, should not be empty (nil or zero length).
 @param value         The key, should not be empty (nil or zero length).
 @param filename      The filename.
 @param extendedData  The extended data for this item (pass nil to ignore it).
 
 @return Whether succeed.
 */

/**
 *  添加缓存
 *
 *  @param key          缓存键值
 *  @param value        缓存对象
 *  @param filename     缓存文件名称
 *         filename     != null
 *                          则用文件缓存value，并把`key`,`filename`,`extendedData`写入数据库
 *         filename     == null
 *                          缓存方式type：YYKVStorageTypeFile 不进行缓存
 *                          缓存方式type：YYKVStorageTypeSQLite || YYKVStorageTypeMixed 数据库缓存
 *  @param extendedData 缓存拓展数据
 */


- (BOOL)saveItemWithKey:(NSString *)key
                  value:(NSData *)value
               filename:(nullable NSString *)filename
           extendedData:(nullable NSData *)extendedData;

#pragma mark - Remove Items
///=============================================================================
/// @name Remove Items
///=============================================================================

//  移除缓存


/**
 Remove an item with 'key'.
 
 @param key The item's key.
 @return Whether succeed.
 */

//移除缓存

/**
 *  删除缓存
 */

- (BOOL)removeItemForKey:(NSString *)key;

/**
 Remove items with an array of keys.
 
 @param keys An array of specified keys.
 
 @return Whether succeed.
 */
- (BOOL)removeItemForKeys:(NSArray<NSString *> *)keys;

/**
 Remove all items which `value` is larger than a specified size.
 
 @param size  The maximum size in bytes.
 @return Whether succeed.
 */

/**
 *  删除所有内存开销大于size的缓存
 */

- (BOOL)removeItemsLargerThanSize:(int)size;

/**
 Remove all items which last access time is earlier than a specified timestamp.
 
 @param time  The specified unix timestamp.
 @return Whether succeed.
 */

/**
 *  删除所有时间比time小的缓存
 */
- (BOOL)removeItemsEarlierThanTime:(int)time;

/**
 Remove items to make the total size not larger than a specified size.
 The least recently used (LRU) items will be removed first.
 
 @param maxSize The specified size in bytes.
 @return Whether succeed.
 */

/**
 *  减小缓存占的容量开销，使总缓存的容量开销值不大于maxSize(删除原则：LRU 最久未使用的缓存将先删除)
 */
- (BOOL)removeItemsToFitSize:(int)maxSize;

/**
 Remove items to make the total count not larger than a specified count.
 The least recently used (LRU) items will be removed first.
 
 @param maxCount The specified item count.
 @return Whether succeed.
 */

/**
 *  减小总缓存数量，使总缓存数量不大于maxCount(删除原则：LRU 最久未使用的缓存将先删除)
 */

- (BOOL)removeItemsToFitCount:(int)maxCount;

/**
 Remove all items in background queue.
 
 @discussion This method will remove the files and sqlite database to a trash
 folder, and then clear the folder in background queue. So this method is much 
 faster than `removeAllItemsWithProgressBlock:endBlock:`.
 
 @return Whether succeed.
 */

/**
 *  清空所有缓存
 */

- (BOOL)removeAllItems;

/**
 Remove all items.
 
 @warning You should not send message to this instance in these blocks.
 @param progress This block will be invoked during removing, pass nil to ignore.
 @param end      This block will be invoked at the end, pass nil to ignore.
 */
- (void)removeAllItemsWithProgressBlock:(nullable void(^)(int removedCount, int totalCount))progress
                               endBlock:(nullable void(^)(BOOL error))end;


#pragma mark - Get Items
///=============================================================================
/// @name Get Items
///=============================================================================

//获取缓存
/**
 Get item with a specified key.
 
 @param key A specified key.
 @return Item for the key, or nil if not exists / error occurs.
 */

/**
 *  读取缓存
 */

- (nullable YYKVStorageItem *)getItemForKey:(NSString *)key;

/**
 Get item information with a specified key.
 The `value` in this item will be ignored.
 
 @param key A specified key.
 @return Item information for the key, or nil if not exists / error occurs.
 */
- (nullable YYKVStorageItem *)getItemInfoForKey:(NSString *)key;

/**
 Get item value with a specified key.
 
 @param key  A specified key.
 @return Item's value, or nil if not exists / error occurs.
 */
- (nullable NSData *)getItemValueForKey:(NSString *)key;

/**
 Get items with an array of keys.
 
 @param keys  An array of specified keys.
 @return An array of `YYKVStorageItem`, or nil if not exists / error occurs.
 */
- (nullable NSArray<YYKVStorageItem *> *)getItemForKeys:(NSArray<NSString *> *)keys;

/**
 Get item infomartions with an array of keys.
 The `value` in items will be ignored.
 
 @param keys  An array of specified keys.
 @return An array of `YYKVStorageItem`, or nil if not exists / error occurs.
 */
- (nullable NSArray<YYKVStorageItem *> *)getItemInfoForKeys:(NSArray<NSString *> *)keys;

/**
 Get items value with an array of keys.
 
 @param keys  An array of specified keys.
 @return A dictionary which key is 'key' and value is 'value', or nil if not 
    exists / error occurs.
 */
- (nullable NSDictionary<NSString *, NSData *> *)getItemValueForKeys:(NSArray<NSString *> *)keys;

#pragma mark - Get Storage Status
///=============================================================================
/// @name Get Storage Status
///=============================================================================


//缓存状态


/**
 Whether an item exists for a specified key.
 
 @param key  A specified key.
 
 @return `YES` if there's an item exists for the key, `NO` if not exists or an error occurs.
 */

/**
 *  判断当前key是否有对应的缓存
 */

- (BOOL)itemExistsForKey:(NSString *)key;

/**
 Get total item count.
 @return Total item count, -1 when an error occurs.
 */

/**
 *  获取缓存总数量
 */

- (int)getItemsCount;

/**
 Get item value's total size in bytes.
 @return Total size in bytes, -1 when an error occurs.
 */

/**
 *  获取缓存总内存开销
 */
- (int)getItemsSize;

@end

NS_ASSUME_NONNULL_END

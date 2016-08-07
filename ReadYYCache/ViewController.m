//
//  ViewController.m
//  ReadYYCache
//
//  Created by lixiaohu on 16/8/3.
//  Copyright © 2016年 lixiaohu. All rights reserved.
//

#import "ViewController.h"
#import "YYCache.h"
#import "User.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];


#pragma mark YYCache的基本使用
    /// 0.初始化YYCache
    YYCache *cache = [YYCache cacheWithName:@"mydb"];
    // 1.缓存普通字符
    [cache setObject:@"lixiaohu" forKey:@"name"];
    NSString *name = (NSString *)[cache objectForKey:@"name"];
    NSLog(@"name: %@", name);
    // 2.缓存模型
    User *user = [[User alloc] init];
    user.name = @"lixiaohu";
    [cache setObject:(id)user forKey:@"user"];
    // 3.缓存数组
    NSMutableArray *array = @[].mutableCopy;
    for (NSInteger i = 0; i < 10; i ++) {
        [array addObject:user];
    }
    // 异步缓存
    [cache setObject:array forKey:@"user" withBlock:^{
        // 异步回调
        NSLog(@"%@", [NSThread currentThread]);
        NSLog(@"array缓存完成....");
    }];
    // 延时读取
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 异步读取
        [cache objectForKey:@"user" withBlock:^(NSString * _Nonnull key, id  _Nonnull object) {
            // 异步回调
            NSLog(@"%@", [NSThread currentThread]);
            NSLog(@"%@", object);
        }];
    });
    
    
    // 如果只想内存缓存，可以直接调用`memoryCache`对象
    YYCache *cache2 = [YYCache cacheWithName:@"aaa"];
    [cache2.memoryCache setObject:@24 forKey:@"age"];
    NSLog(@"age缓存在内存：%d", [cache2.memoryCache containsObjectForKey:@"age"]);
    NSLog(@"age缓存在文件：%d", [cache2.diskCache containsObjectForKey:@"age"]);
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

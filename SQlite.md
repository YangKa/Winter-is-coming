SQlite

1.数据库初始化设置page_size和cache_size

SQLiteh把其存储的数据以page为最小单位进行存储。cache_size的含义为当进行查询操作时，用多少个page来缓存查询结果，加快后续查询相同索引时从缓存中寻找结果的速度。

和table_size、存储的数据类型、可能的增删查改比例有关。

2.事物transaction

可以大大提升内部增删查改的速度。

3.缓存被编译后的sql语句

4.数据库升级

一个数据库版本表，一段升级累加的逻辑。
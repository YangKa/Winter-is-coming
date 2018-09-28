## objc结构体

#### 类结构体

	struct objc_class {			
		struct objc_class *isa;	
		struct objc_class *super_class;	
		const char *name;		
		long version;
		long info;
		long instance_size;
		struct objc_ivar_list *ivars;
	
	#if defined(Release3CompatibilityBuild)
		struct objc_method_list *methods;
	#else
		struct objc_method_list **methodLists;
	#endif
	
		struct objc_cache *cache;
	 	struct objc_protocol_list *protocols;
	};
	
#### 分类机构体	

	typedef struct objc_category *Category;
	
	struct objc_category {
		char *category_name;
		char *class_name;
		struct objc_method_list *instance_methods;
		struct objc_method_list *class_methods;
	 	struct objc_protocol_list *protocols;
	};
	
#### 实例变量列表

	typedef struct objc_ivar *Ivar;

	struct objc_ivar_list {
		int ivar_count;
	#ifdef __alpha__
		int space;
	#endif
		struct objc_ivar {
			char *ivar_name;
			char *ivar_type;
			int ivar_offset;
	#ifdef __alpha__
			int space;
	#endif
		} ivar_list[1];			/* variable length structure */
	};
	
#### 方法列表

	typedef struct objc_method *Method;
	
	struct objc_method_list {
	#if defined(Release3CompatibilityBuild)
	        struct objc_method_list *method_next;
	#else
		struct objc_method_list *obsolete;
	#endif
	
		int method_count;
	#ifdef __alpha__
		int space;
	#endif
		struct objc_method {
			SEL method_name;
			char *method_types;
	                IMP method_imp;
		} method_list[1];		/* variable length structure */
	};
	
#### 方法缓存列表

	struct objc_cache {
		unsigned int mask;            /* total = mask + 1 */
		unsigned int occupied;        
		Method buckets[1];
	};

#### 协议列表
	
	struct objc_protocol_list {
		struct objc_protocol_list *next;
		int count;
		Protocol *list[1];
	};


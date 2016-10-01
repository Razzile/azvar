#include <mach-o/nlist.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <objc/runtime.h>
#include <stdio.h>

struct Variable
{
	const char *name;
	int value;
	int p_value;
};

struct Region
{
	int start;
	int size;
};

@interface TestClass : NSObject {
@public
	int var1;
	bool var2;
}
@end
@implementation TestClass

@end
Variable* FindSymbol(const char* sym);
Variable* FindIvar(const char* sym);
Region* GetReadableRegions(int* out_size, int* start_addr);
bool IsObjcClass(void* ptr);
void mread(void* ptr, size_t size, size_t count, mach_port_t port);

int main(int argc, char** argv)
{
	FindIvar("var1");
	//FindSymbol("blaa");
}

void mread(void* ptr, vm_address_t addr, size_t size, mach_port_t port)
{
	vm_size_t readsize = 0;
	vm_read_overwrite(port, addr, size, (vm_address_t)ptr, &readsize);
}

Variable* FindSymbol(const char* sym)
{
	mach_header *head = (mach_header*)malloc(sizeof(mach_header));
	load_command *l_cmd = (load_command*)malloc(sizeof(load_command));
	segment_command *s_cmd = (segment_command*)malloc(sizeof(segment_command));
	symtab_command *t_cmd = (symtab_command*)malloc(sizeof(symtab_command));

	vm_address_t addr = 0;
	vm_address_t ledit_addr = 0;
	vm_address_t symoff = 0;
	vm_address_t stroff = 0;

	vm_size_t vmsize;
	vm_region_basic_info_data_t info;
	mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
	memory_object_name_t object;

	vm_region(mach_task_self(), &addr, &vmsize, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &info_count, &object);

	//incorporate these into for loop?
	mread(head, addr, sizeof(mach_header), mach_task_self());

	vm_address_t local_addr = addr+sizeof(mach_header);

	for(int i = 0; i < head->ncmds; i++)
	{
		mread(l_cmd, local_addr, sizeof(load_command), mach_task_self());
		if(l_cmd->cmdsize == 0) continue;
		if(l_cmd->cmd == LC_SEGMENT)
		{
			mread(s_cmd, local_addr, sizeof(segment_command), mach_task_self());
			if(strstr(s_cmd->segname, "__LINKEDIT") != NULL)
			{
				ledit_addr = s_cmd->vmaddr; //apply ASLR bias?
			}
		}
		if(l_cmd->cmd == LC_SYMTAB)
		{
			mread(t_cmd, local_addr, sizeof(symtab_command), mach_task_self());
			symoff = t_cmd->symoff;
			stroff = t_cmd->stroff;
			//stroff - symoff is what we want
		}
	}
	if(ledit_addr == 0 || symoff == 0 || stroff == 0) goto fail;
	//for(int j = 0; )




	fail:
		return NULL;
}

Variable* FindIvar(const char* sym)
{
	TestClass *test1 = [TestClass alloc];
	test1->var1 = 999;
	TestClass *test2 = [TestClass alloc];
	int addr = 0; //(int)test1;
	printf("0x%x\n", (int)test1);
	int size = 0;
	Region *regions = GetReadableRegions(&size, &addr);
	for(int v = 0; v <= size; v++)
	{
		if((regions[v].start <= (int)test1) && (regions[v].start + regions[v].size >= (int)test1))
		{
			for(int i = 0; i < regions[v].size; i+=4)
			{
				unsigned int scan = regions[v].start+i;
				Class cls = object_getClass((id)scan);
				if (cls == Nil) continue;
				if (!IsObjcClass(cls))
				{
					continue;
				}

				unsigned int count = 0;
				Ivar *ivar_list = class_copyIvarList(cls, &count);

				for (int j = 0; j < count; j++)
				{
					const char* name = ivar_getName(ivar_list[j]);
					if (name == NULL) continue;
					if (!strcmp(name, sym))
					{
						int var_stack = ivar_getOffset(ivar_list[j]);
						int pointer = (int)test1+var_stack;
						printf("ivar %s = %d (at 0x%x)\n", name, *(int*)pointer, pointer);
					}
				}
				free(ivar_list);
				//free(cls);
			}
		}
	}
	free(regions);
	[test1 release];
	[test2 release];
	return NULL;
}

bool IsObjcClass(void *ptr)
{
	Class testPointerClass = (Class)ptr;
	bool isClass = false;

	int numClasses = objc_getClassList(NULL, 0);
	Class *classesList = (Class *)malloc(sizeof(Class) * numClasses);
	numClasses = objc_getClassList(classesList, numClasses);

	for (int i = 0; i < numClasses; i++)
	{
        if (classesList[i] == testPointerClass)
        {
            isClass = true;
            break;
        }
    }
    free(classesList);
    return isClass;
}


Region* GetReadableRegions(int* out_size, int* start_addr)
{
	vm_address_t address = 0x0;
	kern_return_t status = KERN_SUCCESS;
	if(start_addr != NULL)
	{
		address = *start_addr;
	}
    Region *regions = (Region*)malloc(sizeof(Region) * 1024);
    int count = 0;
    while (status == KERN_SUCCESS && address <= 0xF0000000)
    {

        vm_size_t vmsize;

        vm_region_basic_info_data_t info;
        mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
        memory_object_name_t object;

        status = vm_region(mach_task_self(), &address, &vmsize, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &info_count, &object);

        if(status == KERN_SUCCESS) //to do: check objc classes lie in read/write regions (will reduce memory search time)
        {
        	regions[count].start = address;
        	regions[count].size = vmsize;
        	count++;
        }
        address+=vmsize;
    }

    *out_size = count;
    return regions;
}

	// unsigned int class_count = 0;
	// Class *classes =  objc_copyClassList(&class_count);

	// for (int i = 0; i <= class_count; i++)
	// {
	// 	unsigned int count = 0;
	// 	Ivar *ivar_list = class_copyIvarList(classes[i], &count);
	// 	for (int j = 0; j < count; j++)
	// 	{
	// 		const char* name = ivar_getName(ivar_list[j]);
	// 		if (name == NULL) continue;
	// 		if(!strcmp(name, "var1"))
	// 		{
	// 			//int pointer = ivar_getOffset(ivar_list[j]);
	// 			// printf("0x%x", *(int*)classes[i]+pointer);
	// 		}
	// 	}
	// 	free(ivar_list);
	// }
	// free(classes);
	// printf("%d\n", class_count);

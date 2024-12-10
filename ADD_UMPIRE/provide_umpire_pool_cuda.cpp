#include "umpire/Allocator.hpp"
#include "umpire/ResourceManager.hpp"
#include "umpire/strategy/AlignedAllocator.hpp"
#include "umpire/strategy/DynamicPoolList.hpp"

#include <stdlib.h>


int INITIALIZED=0;

umpire::ResourceManager * umpire_rm = NULL;
umpire::Allocator umpire_aligned_alloc;
umpire::Allocator umpire_pooled_allocator;
std::list<void *> pointer_list; 

#include <new>
#include <stdio.h>

//#ifdef __cplusplus
//extern "C" {
//#endif
//{
void * provide_umpire_pool(size_t N)
{


  if (INITIALIZED==0){

    umpire::ResourceManager& rm_tmp = umpire::ResourceManager::getInstance();
    umpire_rm = &rm_tmp;

#if 1

    umpire_aligned_alloc = umpire_rm->getAllocator("UM");
    umpire_pooled_allocator = umpire_rm->makeAllocator<umpire::strategy::DynamicPoolList>("UM_pool", umpire_aligned_alloc,
		                                                                                   (size_t) 512*1024*1024,
												   (size_t) 1*1024*1024);

#else
   umpire_aligned_alloc =
      umpire_rm->makeAllocator<umpire::strategy::AlignedAllocator>("aligned_allocator", umpire_rm->getAllocator("HOST"), 256);

   umpire_pooled_allocator = umpire_rm->makeAllocator<umpire::strategy::DynamicPoolList>("HOST_pool", umpire_aligned_alloc,
                                                                              (size_t) 10*1024*1024*1024, /* default = 512Mb*/
                                                                              (size_t) 10*1024*1024 /* default = 1Mb */);
#endif
    INITIALIZED=1;
  }


//  char* ptr = new char[N*sizeof(double)];
//  return reinterpret_cast<void*>(ptr);

   void *ptr=NULL;

   ptr = umpire_pooled_allocator.allocate(N*sizeof(double));
   if (ptr == NULL){ 
     fprintf(stderr,"pool: memory allocation of %zu bytes failed\n",N);
     return NULL;
   }
   else{
//     fprintf(stderr,"pool: memory allocation of %zu bytes\n",N);
     pointer_list.push_front(ptr);
   }

   return ptr;

}
//}


//#ifdef __cplusplus
//extern "C" {
//#endif
//{
void free_umpire_pool( void * ptr){
  //delete[] reinterpret_cast<char*> (data) ;
  if (ptr == NULL) return ;

  //check if memory region for ptr was allocated via pool allocator
  
  auto pos = find(pointer_list.begin() , pointer_list.end() , ptr);
  if ( pos != pointer_list.end() ){
  //    fprintf(stderr,"pointer %p was allocated with the memory pool \n",ptr);
      umpire_pooled_allocator.deallocate(ptr);
      pointer_list.erase(pos);
  }
  else
   fprintf(stderr,"pointer %p was NOT allocated withe memory pool \n",ptr);	  
}

//}

bool is_umpire_pool_ptr(void *ptr){

   if (pointer_list.size() == 0 || ptr == NULL)
     return false;

   auto pos = find(pointer_list.begin() , pointer_list.end() , ptr);
   if ( pos != pointer_list.end() )
	return true;
   else
	return false;

}






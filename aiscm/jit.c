#include <libguile.h>
#include <stdint.h>
#include <sys/mman.h>

// http://blog.reverberate.org/2012/12/hello-jit-world-joy-of-simple-jits.html

static scm_t_bits mmap_tag;

struct mmap_t {
  void *mem;
  int len;
};

static struct mmap_t *get_self(SCM scm_self)
{
  scm_assert_smob_type(mmap_tag, scm_self);
  return (struct mmap_t *)SCM_SMOB_DATA(scm_self);
}

size_t free_mmap(SCM scm_self)
{
  struct mmap_t *self = get_self(scm_self);
  munmap(self->mem, self->len);
  scm_gc_free(self, sizeof(struct mmap_t), "mmap");
  return 0;
}

SCM make_mmap(SCM code)
{
  SCM retval;
  struct mmap_t *mem;
  mem = (struct mmap_t *)scm_gc_malloc_pointerless(sizeof(struct mmap_t), "mmap");
  mem->len = SCM_BYTEVECTOR_LENGTH(code);
  mem->mem = mmap(NULL, mem->len, PROT_WRITE | PROT_EXEC,
                  MAP_ANON | MAP_PRIVATE, -1, 0);
  SCM_NEWSMOB(retval, mmap_tag, mem);
  memcpy(mem->mem, SCM_BYTEVECTOR_CONTENTS(code), SCM_BYTEVECTOR_LENGTH(code));
  scm_gc_register_allocation(mem->len);
  return retval;
}

SCM mmap_address(SCM scm_self)
{
  struct mmap_t *self = get_self(scm_self);
#if defined __x86_64__
  return scm_from_int64((int64_t)self->mem);
#else
  return scm_from_int32((int32_t)self->mem);
#endif
}

void init_jit(void)
{
  mmap_tag = scm_make_smob_type("mmap", sizeof(struct mmap_t));
  scm_set_smob_free(mmap_tag, free_mmap);
  scm_c_define_gsubr("make-mmap", 1, 0, 0, make_mmap);
  scm_c_define_gsubr("mmap-address", 1, 0, 0, mmap_address);
}

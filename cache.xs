#include <assert.h>
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <qa/cache.h>

typedef struct cache * qa__cache;

MODULE = qa::cache	PACKAGE = qa::cache

qa::cache
raw_open(CLASS, dir)
	const char * dir
    CODE:
	RETVAL = cache_open(dir);
    OUTPUT:
	RETVAL

void
raw_close(cache)
	qa::cache cache
    CODE:
	cache_close(cache);

void
raw_exists(cache, key)
	qa::cache cache
	SV * key
    CODE:
	STRLEN ksize;
	const void *kdata = SvPVbyte(key, ksize);
	if (!cache_get(cache, kdata, ksize, NULL, NULL))
	    XSRETURN_NO;
	XSRETURN_YES;

SV *
raw_get(cache, key)
	qa::cache cache
	SV * key
    CODE:
	STRLEN ksize;
	const void *kdata = SvPVbyte(key, ksize);
	int vsize;
	void *vdata;
	if (!cache_get(cache, kdata, ksize, &vdata, &vsize))
	    XSRETURN_UNDEF;
	if (vsize == 0)
	    XSRETURN_NO;
	RETVAL = newSV(0);
	assert(((char *) vdata)[vsize] == '\0');
	sv_usepvn_flags(RETVAL, vdata, vsize, SV_HAS_TRAILING_NUL);
    OUTPUT:
	RETVAL

void
raw_put(cache, key, val)
	qa::cache cache
	SV * key
	SV * val
    CODE:
	STRLEN ksize, vsize;
	const void *kdata = SvPVbyte(key, ksize);
	const void *vdata = SvPVbyte(val, vsize);
	cache_put(cache, kdata, ksize, vdata, vsize);

void
raw_clean(cache, days)
	qa::cache cache
	int days
    CODE:
	cache_clean(cache, days);

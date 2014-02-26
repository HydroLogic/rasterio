# The GDAL and OGR driver registry.
# GDAL driver management.

import logging

from rasterio.five import string_types

cdef extern from "cpl_conv.h":
    void    CPLFree (void *ptr)
    void    CPLSetThreadLocalConfigOption (char *key, char *val)
    const char * CPLGetConfigOption ( const char *key, const char *default)

cdef extern from "cpl_error.h":
    void    CPLSetErrorHandler (void *handler)

cdef extern from "gdal.h":
    void GDALAllRegister()
    void GDALDestroyDriverManager()
    int GDALGetDriverCount()

cdef extern from "ogr_api.h":
    void OGRRegisterAll()
    void OGRCleanupAll()
    int OGRGetDriverCount()


log = logging.getLogger('rasterio')
class NullHandler(logging.Handler):
    def emit(self, record):
        pass
log.addHandler(NullHandler())

code_map = {
    0: 0, 
    1: logging.DEBUG, 
    2: logging.WARNING, 
    3: logging.ERROR, 
    4: logging.CRITICAL }

cdef void * errorHandler(int eErrClass, int err_no, char *msg):
    log.log(code_map[eErrClass], "GDAL Error %s: %s", err_no, msg)


def driver_count():
    return GDALGetDriverCount() + OGRGetDriverCount()


cdef class NonExitingDriverManager(object):

    cdef object options

    def __init__(self, **options):
        self.options = options.copy()

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type=None, exc_val=None, exc_tb=None):
        self.stop()

    def start(self):
        cdef const char *key_c
        cdef const char *val_c
        CPLSetErrorHandler(<void *>errorHandler)
        GDALAllRegister()
        OGRRegisterAll()
        if driver_count() == 0:
            raise ValueError("Drivers not registered")
        for key, val in self.options.items():
            key_b = key.upper().encode('utf-8')
            key_c = key_b
            if isinstance(val, string_types):
                val_b = val.encode('utf-8')
            else:
                val_b = ('ON' if val else 'OFF').encode('utf-8')
            val_c = val_b
            CPLSetThreadLocalConfigOption(key_c, val_c)
            log.debug("Option %s=%s", key, CPLGetConfigOption(key_c, NULL))
        return self

    def stop(self):
        pass

cdef class DriverManager(NonExitingDriverManager):

    def __exit__(self, exc_type=None, exc_val=None, exc_tb=None):
        self.stop()

    def stop(self):
        cdef const char *key_c
        GDALDestroyDriverManager()
        OGRCleanupAll()
        CPLSetErrorHandler(NULL)
        if driver_count() != 0:
            raise ValueError("Drivers not de-registered")
        for key in self.options:
            key_b = key.upper().encode('utf-8')
            key_c = key_b
            CPLSetThreadLocalConfigOption(key_c, NULL)


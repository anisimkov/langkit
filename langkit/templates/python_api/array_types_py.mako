## vim: filetype=makopython

<%def name="decl(cls)">

${py_doc(cls)}


class ${pyapi.type_internal_name(cls)}_Struct(ctypes.Structure):
    _fields_ = [('n', ctypes.c_int),
                ('items', ${pyapi.type_internal_name(cls.element_type())} * 1)]


${pyapi.type_internal_name(cls)} = ctypes.POINTER(
    ${pyapi.type_internal_name(cls)}_Struct
)


class ${cls.name().camel}(object):
    """
    Wrapper class for arrays of ${cls.element_type().name()}.
    """

    def __init__(self, c_value):
        self._c_value = c_value
        self._length = c_value.contents.n
        self._items = ctypes.pointer(c_value.contents.items[0])

    def __repr__(self):
        return '<${cls.name().camel} object at {} {}>'.format(
            hex(id(self)),
            list(self)
        )

    def __del__(self):
        _free(self._c_value)
        self._c_value = None
        self._length = None
        self._items = None

    def __len__(self):
        return self._length

    def __getitem__(self, key):
        if not isinstance(key, int):
            raise TypeError('array indices must be integers, not {}'.format(
                type(key)
            ))
        elif not (0 <= key < self._length):
            raise IndexError()
        return ${pyapi.wrap_value('self._items[key]', cls.element_type())}

</%def>

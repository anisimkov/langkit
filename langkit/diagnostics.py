import enum
from os import path
import traceback

from langkit.utils import Colors, assert_type, col


class Diagnostics(object):
    """
    Holder class that'll store the language definition source dir. Meant to
    be called by manage before functions depending on knowing the language
    source dir can be called.
    """
    lang_source_dir = "<invalid dir>"
    has_pending_error = False

    @classmethod
    def set_lang_source_dir(cls, lang_source_dir):
        """
        Set the language definition source directory.
        :type lang_source_dir: str
        """
        cls.lang_source_dir = lang_source_dir


class Location(object):
    """
    Holder for a location in the source code.
    """

    def __init__(self, file, line, text):
        self.file = file
        self.line = line
        self.text = text

    def __repr__(self):
        return "<Location {} {}>".format(self.file, self.line)

    def __str__(self):
        return 'File "{}", line {}'.format(self.file, self.line)


def extract_library_location():
    """
    Use traceback to extract the location of the definition of an entity in
    the language definition using langkit. This relies on
    LangSourceDir.lang_source_dir being set.

    :rtype: Location
    """
    l = [Location(t[0], t[1], t[3])
         for t in traceback.extract_stack()
         if Diagnostics.lang_source_dir in path.abspath(t[0])
         and "manage.py" not in t[0]]
    return l[-1] if l else None


context_stack = []
"""
:type: list[(str, Location, str)]
"""

context_cache = (None, [])
"""
This will be used to cache the last context stack in case of exception.
:type: (Exception, list[(str, Location)])
"""


class Context(object):
    """
    Add context for diagnostics. For the moment this context is constituted
    of a message and a location.
    """

    def __init__(self, message, location, id=""):
        """
        :param str message: The message to display when displaying the
            diagnostic, to contextualize the location.

        :param Location location: The location associated to the context.

        :param str id: A string that is meant to uniquely identify a category
            of diagnostic. Only one message (the latest) will be shown for each
            category when diagnostics are printed. If id is empty (the default)
            then the context has no category, and it will be considered
            unique, and always be shown.
        """
        self.message = message
        self.location = location
        self.id = id

    def __enter__(self):
        context_stack.append((self.message, self.location, self.id))

    def __exit__(self, exc_type, exc_value, traceback):
        del traceback
        del exc_type
        global context_cache
        if exc_value and context_cache[0] != exc_value:
            context_cache = (exc_value, context_stack[:])
        context_stack.pop()

    def __repr__(self):
        return (
            '<diagnostics.Context message={}, location={}, id={}>'.format(
                self.message, self.location, self.id
            )
        )


class DiagnosticError(Exception):
    pass


class Severity(enum.IntEnum):
    """
    Severity of a diagnostic. For the moment we have two levels, warning and
    error. A warning won't end the compilation process, and error will.
    """
    warning = 1
    error = 2
    non_blocking_error = 3


SEVERITY_COLORS = {
    Severity.warning:            Colors.YELLOW,
    Severity.error:              Colors.RED,
    Severity.non_blocking_error: Colors.RED,
}


def format_severity(severity):
    """
    :param Severity severity:
    """
    msg = ('Error'
           if severity == Severity.non_blocking_error else
           severity.name.capitalize())
    return col(msg, Colors.BOLD + SEVERITY_COLORS[severity])


def get_structured_context(recovered=False):
    """
    From the context global structures, return a structured context locations
    list.

    :rtype: list[(str, Location)]
    """
    c = context_cache[1] if recovered else context_stack
    ids = set()
    msgs = []

    # We'll iterate once on diagnostic contexts, to:
    # 1. Remove those with null locations.
    # 2. Only keep one per registered id.
    for ctx_msg, ctx_loc, id in reversed(c):
        if ctx_loc and (not id or id not in ids):
            msgs.append((ctx_msg, ctx_loc))
            ids.add(id)

    return msgs


def print_context(recovered=False):
    """
    Print the current error context.
    """

    # Then we'll print the context we've kept
    last_file_info = ''
    for ctx_msg, ctx_loc in reversed(get_structured_context(recovered)):
        # We only want to show the file information one time if it is the same
        file_info = 'File "{}", '.format(col(ctx_loc.file, Colors.CYAN))
        if last_file_info == file_info:
            file_info = '  '
        else:
            last_file_info = file_info

        print ('{file_info}line {line}, {msg}'.format(
            file_info=file_info,
            line=col(ctx_loc.line, Colors.CYAN),
            msg=ctx_msg
        ))


def get_parsable_location():
    """
    Returns an error location in the common tool parsable format::

        {file}:{line}:{column}

    :rtype: str
    """
    loc = get_structured_context()[0][1]
    return "{}:{}:1".format(path.abspath(loc.file), loc.line)


def check_source_language(predicate, message, severity=Severity.error):
    """
    Check predicates related to the user's input in the input language
    definition. Show error messages and eventually terminate if those error
    messages are critical.

    :param bool predicate: The predicate to check.
    :param str message: The base message to display if predicate happens to
        be false.
    :param Severity severity: The severity of the diagnostic.
    """
    # PyCharm's static analyzer thinks Severity.foo is an int because of the
    # class declaration, it it's really an instance of Severity instead.
    severity = assert_type(severity, Severity)
    if not predicate:
        print_context()
        print "{}{}: {}".format(
            "    " if context_stack else '',
            format_severity(severity),
            message
        )
        if severity == Severity.error:
            raise DiagnosticError()
        elif severity == Severity.non_blocking_error:
            Diagnostics.has_pending_error = True


def check_multiple(predicates_and_messages, severity=Severity.error):
    """
    Helper around check_source_language, check multiple predicates at once.

    :param list[(bool, str)] predicates_and_messages: List of diagnostic
        tuples.
    :param Severity severity: The severity of the diagnostics.
    """
    for predicate, message in predicates_and_messages:
        check_source_language(predicate, message, severity)


def check_type(obj, typ, message=None):
    """
    Like utils.assert_type, but produces a client error instead.

    :param Any obj: The object to check.
    :param T typ: Type parameter. The expected type of obj.
    :param str|None message: The base message to display if type check fails.

    :rtype: T
    """
    try:
        return assert_type(obj, typ)
    except AssertionError as e:
        message = "{}\n{}".format(e.message, message) if message else e.message
        check_source_language(False, message)


def errors_checkpoint():
    """
    If there was a non-blocking error, exit the compilation process.
    """
    if Diagnostics.has_pending_error:
        raise DiagnosticError()

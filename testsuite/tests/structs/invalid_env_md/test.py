"""
Test that invalid environment metadata structs are properly rejected.
"""

from __future__ import absolute_import, division, print_function

import langkit
from langkit.diagnostics import DiagnosticError
from langkit.dsl import ASTNode, Struct, T, UserField, env_metadata
from langkit.parsers import Grammar

from utils import emit_and_print_errors


def run(md_constructor):
    """
    Emit and print he errors we get for the below grammar. `md_constructor` is
    called to create the lexical environment metadata.
    """

    print('== {} =='.format(md_constructor.__name__))

    class FooNode(ASTNode):
        pass

    class Example(FooNode):
        pass

    grammar = Grammar('main_rule')
    grammar.add_rules(main_rule=Example('example'))

    try:
        md_constructor()
    except DiagnosticError:
        langkit.reset()
    else:
        emit_and_print_errors(grammar)
    print('')


def not_a_struct():
    @env_metadata
    class Metadata(object):
        pass


def two_md():
    @env_metadata
    class Metadata(Struct):
        pass

    del Metadata

    @env_metadata
    class Metadata(Struct):
        pass


def bad_name():
    @env_metadata
    class BadName(Struct):
        pass


def bad_type():
    @env_metadata
    class Metadata(Struct):
        fld = UserField(type=T.AnalysisUnit)


run(not_a_struct)
run(two_md)
run(bad_name)
run(bad_type)
print('Done')

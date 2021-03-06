"""
Test that Symbol bindings in the Python API are properly working.
"""

from __future__ import absolute_import, division, print_function

from langkit.compile_context import LibraryEntity
from langkit.dsl import ASTNode, Symbol
from langkit.expressions import langkit_property
from langkit.parsers import Grammar

from lexer_example import Token
from utils import build_and_run


class FooNode(ASTNode):
    pass


class Example(FooNode):
    token_node = True

    @langkit_property(public=True, return_type=Symbol)
    def sym(sym=Symbol):
        return sym


foo_grammar = Grammar('main_rule')
foo_grammar.add_rules(
    main_rule=Example(Token.Identifier),
)

build_and_run(foo_grammar, 'main.py',
              symbol_canonicalizer=LibraryEntity('Pkg', 'Canonicalize'))
print('Done')

from __future__ import absolute_import, division, print_function

from langkit.dsl import ASTNode, LexicalEnv
from langkit.expressions import DynamicVariable, Property, Self
from langkit.parsers import Grammar

from lexer_example import Token
from utils import emit_and_print_errors


Env = DynamicVariable('env', LexicalEnv)


def run(expr):
    """
    Emit and print the errors we get for the below grammar for the given
    "expr" property expression.
    """

    print('== {} =='.format(expr))

    class FooNode(ASTNode):
        pass

    class ExampleNode(FooNode):
        token_node = True

        implicit_prop = Property(Self.as_bare_entity, dynamic_vars=[Env])

        prop = Property(expr, public=True)
        use_implicit_prop = Property(
            Env.bind(Self.node_env, Self.implicit_prop),
            public=True
        )

    grammar = Grammar('main_rule')
    grammar.add_rules(main_rule=ExampleNode(Token.Example))
    emit_and_print_errors(grammar)
    Env.unfreeze()
    print('')


run(Env.get(Self.tok))
run(Self.implicit_prop)
run(Env.bind(Self.node_env, Env.get(Self)))
run(Env.bind(Self.node_env, Self.implicit_prop))
print('Done')

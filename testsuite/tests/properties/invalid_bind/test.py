from __future__ import absolute_import, division, print_function

from langkit.diagnostics import WarningSet
from langkit.dsl import ASTNode, LexicalEnv, LogicVar, T, UserField
from langkit.expressions import (Bind, DynamicVariable, Property, Self, Var,
                                 langkit_property, ignore)
from langkit.parsers import Grammar, Or

from utils import emit_and_print_errors, default_warning_set


warning_set = default_warning_set.with_disabled(WarningSet.unused_bindings)


def run(name, eq_prop):
    """
    Emit and print the errors we get for the below grammar with "expr" as
    a property in BarNode.
    """

    env = DynamicVariable('env', LexicalEnv)
    dyn_node = DynamicVariable('dyn_node', T.BazNode)

    print('== {} =='.format(name))

    eq_prop = eval(eq_prop)

    class FooNode(ASTNode):
        ref_var = UserField(LogicVar, public=False)
        type_var = UserField(LogicVar, public=False)

    class BarNode(FooNode):
        main_prop = Property(
            env.bind(Self.node_env,
                     Bind(Self.type_var, Self.ref_var, eq_prop=eq_prop))
        )

        @langkit_property(public=True)
        def wrapper():
            _ = Var(Self.main_prop)
            ignore(_)
            return Self.as_bare_entity

    class BazNode(FooNode):
        prop = Property(12, warn_on_unused=False)
        prop2 = Property(True, warn_on_unused=False)

        @langkit_property(warn_on_unused=False)
        def prop3(_=T.BarNode):
            return True

        @langkit_property(warn_on_unused=False, dynamic_vars=[dyn_node])
        def prop4(other=T.BazNode.entity):
            return other.node == dyn_node

        @langkit_property(warn_on_unused=False)
        def prop_a(other=T.BazNode.entity):
            return Self.as_entity == other

        @langkit_property(warn_on_unused=False, dynamic_vars=[env])
        def prop_b(other=T.BazNode.entity):
            return other.node_env == env

    grammar = Grammar('main_rule')
    grammar.add_rules(
        main_rule=Or(
            BarNode('example'),
            BazNode('example'),
        )
    )
    emit_and_print_errors(grammar, warning_set=warning_set)
    print('')


run('Incorrect bind eq_prop 1', 'T.BazNode.prop')
run('Incorrect bind eq_prop 2', 'T.BazNode.prop2')
run('Incorrect bind eq_prop 3', 'T.BazNode.prop3')
run('Incorrect bind eq_prop 4', 'T.BazNode.prop4')
run('Correct bind eq_prop A', 'T.BazNode.prop_a')
run('Correct bind eq_prop B', 'T.BazNode.prop_b')
print('Done')

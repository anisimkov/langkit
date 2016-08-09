## vim: filetype=makoada

<%namespace name="array_types"   file="array_types_ada.mako" />
<%namespace name="struct_types"  file="struct_types_ada.mako" />

<% root_node_array = T.root_node.array_type() %>

with Ada.Containers; use Ada.Containers;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Ordered_Maps;
with Ada.Text_IO;    use Ada.Text_IO;
with Ada.Unchecked_Deallocation;

with System.Storage_Elements;    use System.Storage_Elements;

with Langkit_Support.Extensions; use Langkit_Support.Extensions;
with Langkit_Support.PP_Utils;   use Langkit_Support.PP_Utils;
with Langkit_Support.Relative_Get;
with Langkit_Support.Symbols;    use Langkit_Support.Symbols;

pragma Warnings (Off, "referenced");
with Adalog.Abstract_Relation;   use Adalog.Abstract_Relation;
with Adalog.Debug;
with Adalog.Operations;          use Adalog.Operations;
with Adalog.Predicates;          use Adalog.Predicates;
with Adalog.Pure_Relations;      use Adalog.Pure_Relations;
with Adalog.Variadic_Operations; use Adalog.Variadic_Operations;
pragma Warnings (On, "referenced");

package body ${_self.ada_api_settings.lib_name}.AST is

   ${array_types.body(LexicalEnvType.array_type())}
   ${array_types.body(EnvElement.array_type())}
   ${array_types.body(root_node_array)}

   function Child_Number
     (Node : access ${root_node_value_type}'Class)
      return Positive
      with Pre => Node.Parent /= null;
   --  Return the 1-based index for Node in its parents' children

   -----------
   -- Child --
   -----------

   function Child (Node  : access ${root_node_value_type}'Class;
                   Index : Positive) return ${root_node_type_name}
   is
      Result : ${root_node_type_name};
      Exists : Boolean;
   begin
      Get_Child (Node, Index, Exists, Result);
      return (if Exists then Result else null);
   end Child;

   --------------
   -- Traverse --
   --------------

   function Traverse
     (Node  : access ${root_node_value_type}'Class;
      Visit : access function (Node : access ${root_node_value_type}'Class)
              return Visit_Status)
     return Visit_Status
   is
      Status : Visit_Status := Into;

   begin
      if Node /= null then
         Status := Visit (Node);

         --  Skip processing the child nodes if the returned status is Over
         --  or Stop. In the former case the previous call to Visit has taken
         --  care of processing the needed childs, and in the latter case we
         --  must immediately stop processing the tree.

         if Status = Into then
            for I in 1 .. Child_Count (Node) loop
               declare
                  Cur_Child : constant ${root_node_type_name} :=
                     Child (Node, I);

               begin
                  if Cur_Child /= null then
                     Status := Traverse (Cur_Child, Visit);
                     exit when Status /= Into;
                  end if;
               end;
            end loop;
         end if;
      end if;

      if Status = Stop then
         return Stop;

      --  At this stage the Over status has no sense and we just continue
      --  processing the tree.

      else
         return Into;
      end if;
   end Traverse;

   --------------
   -- Traverse --
   --------------

   procedure Traverse
     (Node  : access ${root_node_value_type}'Class;
      Visit : access function (Node : access ${root_node_value_type}'Class)
                               return Visit_Status)
   is
      Result_Status : Visit_Status;
      pragma Unreferenced (Result_Status);
   begin
      Result_Status := Traverse (Node, Visit);
   end Traverse;

   ------------------------
   -- Traverse_With_Data --
   ------------------------

   function Traverse_With_Data
     (Node  : access ${root_node_value_type}'Class;
      Visit : access function (Node : access ${root_node_value_type}'Class;
                               Data : in out Data_type)
                               return Visit_Status;
      Data  : in out Data_Type)
      return Visit_Status
   is
      function Helper (Node : access ${root_node_value_type}'Class)
                       return Visit_Status;

      ------------
      -- Helper --
      ------------

      function Helper (Node : access ${root_node_value_type}'Class)
                       return Visit_Status
      is
      begin
         return Visit (Node, Data);
      end Helper;

      Saved_Data : Data_Type;
      Result     : Visit_Status;

   begin
      if Reset_After_Traversal then
         Saved_Data := Data;
      end if;
      Result := Traverse (Node, Helper'Access);
      if Reset_After_Traversal then
         Data := Saved_Data;
      end if;
      return Result;
   end Traverse_With_Data;

   --------------
   -- Traverse --
   --------------

   function Traverse
     (Root : access ${root_node_value_type}'Class)
      return Traverse_Iterator
   is
   begin
      return Create (Root);
   end Traverse;

   ----------
   -- Next --
   ----------

   function Next (It       : in out Find_Iterator;
                  Element  : out ${root_node_type_name}) return Boolean
   is
   begin
      while Next (It.Traverse_It, Element) loop
         if It.Predicate.Evaluate (Element) then
            return True;
         end if;
      end loop;
      return False;
   end Next;

   --------------
   -- Finalize --
   --------------

   overriding
   procedure Finalize (It : in out Find_Iterator) is
   begin
      Destroy (It.Predicate);
   end Finalize;

   ----------
   -- Next --
   ----------

   overriding function Next
     (It       : in out Local_Find_Iterator;
      Element  : out ${root_node_type_name}) return Boolean is
   begin
      while Next (It.Traverse_It, Element) loop
         if It.Predicate (Element) then
            return True;
         end if;
      end loop;
      return False;
   end Next;

   ----------
   -- Find --
   ----------

   function Find
     (Root      : access ${root_node_value_type}'Class;
      Predicate : access function (N : ${root_node_type_name}) return Boolean)
     return Local_Find_Iterator
   is
   begin
      return Ret : Local_Find_Iterator do
         Ret.Traverse_It := Traverse (Root);
         --  We still want to provide this functionality, even though it is
         --  unsafe. TODO: We might be able to make a safe version of this
         --  using generics. Still would be more verbose though.
         Ret.Predicate   := Predicate'Unrestricted_Access.all;
      end return;
   end Find;

   ----------
   -- Find --
   ----------

   function Find
     (Root      : access ${root_node_value_type}'Class;
      Predicate : ${root_node_type_name}_Predicate)
      return Find_Iterator
   is
   begin
      return (Ada.Finalization.Limited_Controlled with
              Traverse_It => Traverse (Root),
              Predicate   => Predicate);
   end Find;

   ----------------
   -- Find_First --
   ----------------

   function Find_First
     (Root      : access ${root_node_value_type}'Class;
      Predicate : ${root_node_type_name}_Predicate)
      return ${root_node_type_name}
   is
      I      : Find_Iterator := Find (Root, Predicate);
      Result : ${root_node_type_name};
   begin
      if not I.Next (Result) then
         Result := null;
      end if;
      return Result;
   end Find_First;

   --------------
   -- Evaluate --
   --------------

   function Evaluate
     (P : access ${root_node_type_name}_Kind_Filter;
      N : ${root_node_type_name})
      return Boolean
   is
   begin
      return N.Kind = P.Kind;
   end Evaluate;

   ----------------
   -- Sloc_Range --
   ----------------

   function Sloc_Range
     (Node : access ${root_node_value_type}'Class;
      Snap : Boolean := False) return Source_Location_Range
   is
      TDH                  : Token_Data_Handler renames
         Node.Unit.Token_Data.all;
      Sloc_Start, Sloc_End : Source_Location;

      function Get (Index : Token_Index) return Token_Data_Type is
        (Get_Token (TDH, Index));

   begin
      if Snap then
         declare
            Tok_Start : constant Token_Index :=
              Token_Index'Max (Node.Token_Start - 1, 0);
            Tok_End : constant Token_Index :=
              Token_Index'Min (Node.Token_End + 1, Last_Token (TDH));
         begin
            Sloc_Start := End_Sloc (Get (Tok_Start).Sloc_Range);
            Sloc_End :=
              Start_Sloc (Get (Tok_End).Sloc_Range);
         end;
      else
         Sloc_Start := Start_Sloc (Get (Node.Token_Start).Sloc_Range);
         Sloc_End := End_Sloc (Get (Node.Token_End).Sloc_Range);
      end if;
      return Make_Range (Sloc_Start, Sloc_End);
   end Sloc_Range;

   ------------
   -- Lookup --
   ------------

   function Lookup (Node : access ${root_node_value_type}'Class;
                    Sloc : Source_Location;
                    Snap : Boolean := False) return ${root_node_type_name}
   is
      Position : Relative_Position;
      Result   : ${root_node_type_name};
   begin
      if Sloc = No_Source_Location then
         return null;
      end if;

      Lookup_Relative (Node, Sloc, Position, Result, Snap);
      return Result;
   end Lookup;

   -------------
   -- Compare --
   -------------

   function Compare (Node : access ${root_node_value_type}'Class;
                     Sloc : Source_Location;
                     Snap : Boolean := False) return Relative_Position is
   begin
      return Compare (Sloc_Range (Node, Snap), Sloc);
   end Compare;

   -------------------
   -- Get_Extension --
   -------------------

   function Get_Extension
     (Node : access ${root_node_value_type}'Class;
      ID   : Extension_ID;
      Dtor : Extension_Destructor) return Extension_Access
   is
      use Extension_Vectors;
   begin
      for Slot of Node.Extensions loop
         if Slot.ID = ID then
            return Slot.Extension;
         end if;
      end loop;

      declare
         New_Ext : constant Extension_Access :=
           new Extension_Type'(Extension_Type (System.Null_Address));
      begin
         Append (Node.Extensions,
                 Extension_Slot'(ID        => ID,
                                 Extension => New_Ext,
                                 Dtor      => Dtor));
         return New_Ext;
      end;
   end Get_Extension;

   ---------------------
   -- Free_Extensions --
   ---------------------

   procedure Free_Extensions (Node : access ${root_node_value_type}'Class) is
      procedure Free is new Ada.Unchecked_Deallocation
        (Extension_Type, Extension_Access);
      use Extension_Vectors;
      Slot : Extension_Slot;
   begin
      --  Explicit iteration for perf
      for J in First_Index (Node.Extensions) .. Last_Index (Node.Extensions)
      loop
         Slot := Get (Node.Extensions, J);
         Slot.Dtor (Node, Slot.Extension.all);
         Free (Slot.Extension);
      end loop;
   end Free_Extensions;

   ---------------------
   -- Lookup_Relative --
   ---------------------

   procedure Lookup_Relative
     (Node       : access ${root_node_value_type}'Class;
      Sloc       : Source_Location;
      Position   : out Relative_Position;
      Node_Found : out ${root_node_type_name};
      Snap       : Boolean := False) is
      Result : constant Relative_Position :=
        Compare (Node, Sloc, Snap);
   begin
      Position := Result;
      Node_Found := (if Result = Inside
                     then Node.Lookup_Children (Sloc, Snap)
                     else null);
   end Lookup_Relative;

   --------------
   -- Children --
   --------------

   function Children
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_type_name}_Arrays.Array_Type
   is
      <% array_pkg = '{}_Arrays'.format(root_node_type_name) %>

      First : constant Integer := ${array_pkg}.Index_Type'First;
      Last  : constant Integer := First + Child_Count (Node) - 1;
   begin
      return A : ${array_pkg}.Array_Type (First .. Last)
      do
         for I in First .. Last loop
            A (I) := Child (Node, I);
         end loop;
      end return;
   end Children;

   function Children
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_array.name()}
   is
      C : ${root_node_type_name}_Arrays.Array_Type := Children (Node);
   begin
      return Ret : ${root_node_array.name()} := Create (C'Length) do
         Ret.Items := C;
      end return;
   end Children;

   -----------------
   -- First_Token --
   -----------------

   function First_Token (TDH : Token_Data_Handler_Access) return Token_Type is
      use Token_Vectors, Trivia_Vectors, Integer_Vectors;
   begin
      if Length (TDH.Tokens_To_Trivias) = 0
         or else (First_Element (TDH.Tokens_To_Trivias)
                  = Integer (No_Token_Index))
      then
         --  There is no leading trivia: return the first token

         return (if Length (TDH.Tokens) = 0
                 then No_Token
                 else (TDH,
                       Token_Index (First_Index (TDH.Tokens)),
                       No_Token_Index));

      else
         return (TDH, No_Token_Index, Token_Index (First_Index (TDH.Trivias)));
      end if;
   end First_Token;

   ----------------
   -- Last_Token --
   ----------------

   function Last_Token (TDH : Token_Data_Handler_Access) return Token_Type is
      use Token_Vectors, Trivia_Vectors, Integer_Vectors;
   begin
      if Length (TDH.Tokens_To_Trivias) = 0
           or else
         Last_Element (TDH.Tokens_To_Trivias) = Integer (No_Token_Index)
      then
         --  There is no trailing trivia: return the last token

         return (if Length (TDH.Tokens) = 0
                 then No_Token
                 else (TDH,
                       Token_Index (Last_Index (TDH.Tokens)),
                       No_Token_Index));

      else
         return (TDH, No_Token_Index, Token_Index (First_Index (TDH.Trivias)));
      end if;
   end Last_Token;

   ---------
   -- "<" --
   ---------

   function "<" (Left, Right : Token_Type) return Boolean is
      pragma Assert (Left.TDH = Right.TDH);
   begin
      if Left.Token < Right.Token then
         return True;

      elsif Left.Token = Right.Token then
         return Left.Trivia < Right.Trivia;

      else
         return False;
      end if;
   end "<";

   ----------
   -- Next --
   ----------

   function Next (Token : Token_Type) return Token_Type is
   begin
      if Token.TDH = null then
         return No_Token;
      end if;

      declare
         use Token_Vectors, Trivia_Vectors, Integer_Vectors;
         TDH : Token_Data_Handler renames Token.TDH.all;

         function Next_Token return Token_Type is
           (if Token.Token < Token_Index (Last_Index (TDH.Tokens))
            then (Token.TDH, Token.Token + 1, No_Token_Index)
            else No_Token);
         --  Return a reference to the next token (not trivia) or No_Token if
         --  Token was the last one.

      begin
         if Token.Trivia /= No_Token_Index then
            --  Token is a reference to a trivia: take the next trivia if it
            --  exists, or escalate to the next token otherwise.

            declare
               Tr : constant Trivia_Node :=
                  Get (TDH.Trivias, Natural (Token.Trivia));
            begin
               return (if Tr.Has_Next
                       then (Token.TDH, Token.Token, Token.Trivia + 1)
                       else Next_Token);
            end;

         else
            --  Thanks to the guard above, we cannot get to the declare block
            --  for the No_Token case, so if Token does not refers to a trivia,
            --  it must be a token.

            pragma Assert (Token.Token /= No_Token_Index);

            --  If there is no trivia, just go to the next token

            if Length (TDH.Tokens_To_Trivias) = 0 then
               return Next_Token;
            end if;

            --  If this token has trivia, return a reference to the first one,
            --  otherwise get the next token.

            declare
               Tr_Index : constant Token_Index := Token_Index
                 (Get (TDH.Tokens_To_Trivias, Natural (Token.Token) + 1));
            begin
               return (if Tr_Index = No_Token_Index
                       then Next_Token
                       else (Token.TDH, Token.Token, Tr_Index));
            end;
         end if;
      end;
   end Next;

   --------------
   -- Previous --
   --------------

   function Previous (Token : Token_Type) return Token_Type is
   begin
      if Token.TDH = null then
         return No_Token;
      end if;

      declare
         use Token_Vectors, Trivia_Vectors, Integer_Vectors;
         TDH : Token_Data_Handler renames Token.TDH.all;
      begin
         if Token.Trivia = No_Token_Index then
            --  Token is a regular token, so the previous token is either the
            --  last trivia of the previous regular token, either the previous
            --  regular token itself.
            declare
               Prev_Trivia : Token_Index;
            begin
               --  Get the index of the trivia that is right bofre Token (if
               --  any).
               if Length (TDH.Tokens_To_Trivias) = 0 then
                  Prev_Trivia := No_Token_Index;

               else
                  Prev_Trivia := Token_Index
                    (Get (TDH.Tokens_To_Trivias, Natural (Token.Token)));
                  while Prev_Trivia /= No_Token_Index
                           and then
                        Get (TDH.Trivias, Natural (Prev_Trivia)).Has_Next
                  loop
                     Prev_Trivia := Prev_Trivia + 1;
                  end loop;
               end if;

               --  If there is no such trivia and Token was the first one, then
               --  this was the start of the token stream: no previous token.
               if Prev_Trivia = No_Token_Index
                  and then Token.Token <= First_Token_Index
               then
                  return No_Token;
               else
                  return (Token.TDH, Token.Token - 1, Prev_Trivia);
               end if;
            end;

         --  Past this point: Token is known to be a trivia

         elsif Token.Trivia = First_Token_Index then
            --  This is the first trivia for some token, so the previous token
            --  cannot be a trivia.
            return (if Token.Token = No_Token_Index
                    then No_Token
                    else (Token.TDH, Token.Token, No_Token_Index));

         elsif Token.Token = No_Token_Index then
            --  This is a leading trivia and not the first one, so the previous
            --  token has to be a trivia.
            return (Token.TDH, No_Token_Index, Token.Trivia - 1);

         --  Past this point: Token is known to be a trivia *and* it is not a
         --  leading trivia.

         else
            return (Token.TDH,
                    Token.Token,
                    (if Get (TDH.Trivias, Natural (Token.Trivia - 1)).Has_Next
                     then Token.Trivia - 1
                     else No_Token_Index));
         end if;
      end;
   end Previous;

   ----------
   -- Data --
   ----------

   function Data (T : Token_Type) return Token_Data_Type is
   begin
      return (if T.Trivia = No_Token_Index
              then Token_Vectors.Get (T.TDH.Tokens, Natural (T.Token))
              else Trivia_Vectors.Get (T.TDH.Trivias, Natural (T.Trivia)).T);
   end Data;

   -----------
   -- Image --
   -----------

   function Image (Token : Token_Type) return String is
      D : constant Token_Data_Type := Data (Token);
   begin
      return (if D.Text = null
              then Token_Kind_Name (D.Kind)
              else Image (D.Text.all));
   end Image;

   --------------------------
   -- Children_With_Trivia --
   --------------------------

   function Children_With_Trivia
     (Node : access ${root_node_value_type}'Class)
      return Children_Arrays.Array_Type
   is
      use Children_Vectors;

      Ret_Vec : Children_Vectors.Vector;
      TDH     : Token_Data_Handler renames Node.Unit.Token_Data.all;

      procedure Append_Trivias (First, Last : Token_Index);
      --  Append all the trivias of tokens between indices First and Last to
      --  the returned vector.

      procedure Append_Trivias (First, Last : Token_Index) is
      begin
         for I in First .. Last loop
            for D of Get_Trivias (TDH, I) loop
               Append (Ret_Vec, (Kind => Trivia, Trivia => D));
            end loop;
         end loop;
      end Append_Trivias;

      function Not_Null (N : ${root_node_type_name}) return Boolean is
        (N /= null);

      First_Child : constant ${root_node_type_name}_Arrays.Index_Type :=
         ${root_node_type_name}_Arrays.Index_Type'First;
      N_Children  : constant ${root_node_type_name}_Arrays.Array_Type
        := ${root_node_type_name}_Arrays.Filter
          (Children (Node), Not_Null'Access);
   begin
      if N_Children'Length > 0
        and then Node.Token_Start /= N_Children (First_Child).Token_Start
      then
         Append_Trivias (Node.Token_Start,
                         N_Children (First_Child).Token_Start - 1);
      end if;

      for I in N_Children'Range loop
         Append (Ret_Vec, Child_Record'(Child, N_Children (I)));
         Append_Trivias (N_Children (I).Token_End,
                         (if I = N_Children'Last
                          then Node.Token_End - 1
                          else N_Children (I + 1).Token_Start - 1));
      end loop;

      return A : constant Children_Arrays.Array_Type := To_Array (Ret_Vec) do
         --  Don't forget to free Ret_Vec, since its memory is not
         --  automatically managed.
         Destroy (Ret_Vec);
      end return;
   end Children_With_Trivia;

   --------------
   -- Node_Env --
   --------------

   function Node_Env
     (Node : access ${root_node_value_type})
      return AST_Envs.Lexical_Env
   is (Node.Self_Env);

   ------------------
   -- Children_Env --
   ------------------

   function Children_Env
     (Node : access ${root_node_value_type})
      return AST_Envs.Lexical_Env
   is (Node.Self_Env);

   ---------------
   -- PP_Trivia --
   ---------------

   procedure PP_Trivia
     (Node : access ${root_node_value_type}'Class;
      Level : Integer := 0)
   is
   begin
      Put_Line (Level, Kind_Name (Node));
      for C of Children_With_Trivia (Node) loop
         case C.Kind is
            when Trivia =>
               Put_Line (Level + 1, (if C.Trivia.Text = null
                                     then ""
                                     else Image (C.Trivia.Text.all)));
            when Child =>
               PP_Trivia (C.Node, Level + 1);
         end case;
      end loop;
   end PP_Trivia;

   use AST_Envs;

   --------------------------
   -- Populate_Lexical_Env --
   --------------------------

   procedure Populate_Lexical_Env
     (Node     : access ${root_node_value_type}'Class;
      Root_Env : AST_Envs.Lexical_Env)
   is

      --  The internal algorithm, as well as the Do_Env_Action implementations,
      --  use an implicit stack of environment, where the topmost
      --  environment (Current_Env parameter) is mutable.
      --
      --  - We want to be able to replace the topmost env that will be seen by
      --    subsequent nodes. This is to support constructs such as use clauses
      --    in ada where you can do stuff like this::
      --
      --        declare  -- new LexicalEnv Lex_1 introduced
      --           A : Integer;
      --           B : Integer := A; -- Will get A from Lex_1
      --           use Foo;
      --           -- We create a new env, Lex_2, from Lex_1, where you can now
      --           -- reference stuff from foo, and for every subsequent
      --           -- declaration, Lex_2 will be the lexical environment !
      --
      --           C : Integer := D
      --           -- F was gotten from Foo which is reachable from Lex_2
      --        begin
      --           ...
      --        end;
      --
      --    In this example, the topmost env on the stack will be *replaced*
      --    when we evaluate env actions for the use clause, but the env that
      --    was previously on the top of the stack *won't change*, so stuff
      --    from Foo will still not be reachable to declarations/statements
      --    before the use clause. This allows to decouple env construction and
      --    symbol resolution in two passes, rather than interleave the two
      --    like in the GNAT compiler.

      procedure Populate_Internal
        (Node        : access ${root_node_value_type}'Class;
         Current_Env : in out Lexical_Env);

      -----------------------
      -- Populate_Internal --
      -----------------------

      procedure Populate_Internal
        (Node        : access ${root_node_value_type}'Class;
         Current_Env : in out Lexical_Env)
      is
         Children_Env : Lexical_Env;
      begin
         if Node = null then
            return;
         end if;

         --  By default (i.e. unless Do_Env_Actions does something special),
         --  the environment we store in Node is the current one.
         Node.Self_Env := Current_Env;

         --  Call Do_Env_Actions on the Node. This might:
         --  1. Mutate Current_Env, eg. replace it with a new env derived from
         --     Current_Env.
         --  2. Return a new env, that will be used as the Current_Env for
         --     Node's children.
         Children_Env := Node.Do_Env_Actions (Current_Env);

         --  Call recursively on children. Use the Children_Env if available,
         --  else pass the existing Current_Env.
         for Child of ${root_node_type_name}_Arrays.Array_Type'
            (Children (Node))
         loop
            if Children_Env = null then
               Populate_Internal (Child, Current_Env);
            else
               Populate_Internal (Child, Children_Env);
            end if;
         end loop;

         Node.Post_Env_Actions (Current_Env);
      end Populate_Internal;

      Env : AST_Envs.Lexical_Env := Root_Env;
   begin
      Populate_Internal (Node, Env);
   end Populate_Lexical_Env;

   -----------------
   -- Short_Image --
   -----------------

   function Short_Image
     (Node : access ${root_node_value_type})
      return Text_Type
   is
      Self : access ${root_node_value_type}'Class := Node;
   begin
      return "<" & To_Text (Kind_Name (Self))
             & " " & To_Text (Image (Sloc_Range (Node))) & ">";
   end Short_Image;

   ------------------------
   -- Address_To_Id_Maps --
   ------------------------

   --  Those maps are used to give unique ids to lexical envs while pretty
   --  printing them.

   function Hash (S : Lexical_Env) return Hash_Type is
     (Hash_Type (To_Integer (S.all'Address)));

   package Address_To_Id_Maps is new Ada.Containers.Hashed_Maps
     (Lexical_Env, Positive, Hash, "=");

   -----------------
   -- Sorted_Envs --
   -----------------

   --  Those ordered maps are used to have a stable representation of internal
   --  lexical environments, which is not the case with hashed maps.

   function "<" (L, R : Symbol_Type) return Boolean
   is
     (L.all < R.all);

   package Sorted_Envs is new Ada.Containers.Ordered_Maps
     (Symbol_Type,
      Element_Type    => AST_Envs.Env_Element_Vectors.Vector,
      "<"             => "<",
      "="             => AST_Envs.Env_Element_Vectors."=");

   -------------------
   -- To_Sorted_Env --
   -------------------

   function To_Sorted_Env (Env : Internal_Envs.Map) return Sorted_Envs.Map is
      Ret_Env : Sorted_Envs.Map;
      use Internal_Envs;
   begin
      for El in Env.Iterate loop
         Ret_Env.Include (Key (El), Element (El));
      end loop;
      return Ret_Env;
   end To_Sorted_Env;


   ----------
   -- Dump --
   ----------

   procedure Dump_One_Lexical_Env
     (Self          : AST_Envs.Lexical_Env; Env_Id : String := "";
      Parent_Env_Id : String := "")
   is
      use Sorted_Envs;

      function Image (El : Env_Element) return String is
        (Image (Short_Image (El.El)));
      -- TODO??? This is slightly hackish, because we're converting a wide
      -- string back to string. But since we're using this solely for
      -- test/debug purposes, it should not matter. Still, would be good to
      -- have Text_Type everywhere at some point.

      function Image is new AST_Envs.Env_Element_Vectors.Image (Image);

   begin
      Put ("<LexEnv (Id" & Env_Id & ", Parent"
           & (if Self.Parent /= null then Parent_Env_Id else " null")
           & "), ");

      if Self.Env.Is_Empty then
         Put_Line ("empty>");
      else
         Put_Line ("{");
         for El in To_Sorted_Env (Self.Env.all).Iterate loop
            Put ("    ");
            Put_Line (Langkit_Support.Text.Image (Key (El).all) & ": "
                 & Image (Element (El)));
         end loop;
         Put_Line ("}>");
      end if;
   end Dump_One_Lexical_Env;
   --  This procedure dumps *one* lexical environment


   ----------------------
   -- Dump_Lexical_Env --
   ----------------------

   procedure Dump_Lexical_Env
     (Node     : access ${root_node_value_type}'Class;
      Root_Env : AST_Envs.Lexical_Env)
   is
      use Address_To_Id_Maps;

      Env_Ids        : Address_To_Id_Maps.Map;
      Current_Env_Id : Positive := 1;

      ----------------
      -- Get_Env_Id --
      ----------------

      function Get_Env_Id (E : Lexical_Env) return String is
         C        : Address_To_Id_Maps.Cursor;
         Inserted : Boolean;
      begin
         if E = Root_Env then
            return " <root>";
         elsif E = null then
            return " <null>";
         end if;

         Env_Ids.Insert (E, Current_Env_Id, C, Inserted);
         if Inserted then
            Current_Env_Id := Current_Env_Id + 1;
         end if;
         return Address_To_Id_Maps.Element (C)'Img;
      end Get_Env_Id;
      --  Retrieve the Id for a lexical env. Assign one if none was yet
      --  assigned.

      --------------
      -- Internal --
      --------------

      Env : Lexical_Env := null;

      procedure Internal (Current : ${root_node_type_name}) is
      begin
         if Current = null then
            return;
         end if;

         --  We only dump environments that we haven't dumped before. This way
         --  we'll only dump environments at the site of their creation, and
         --  not in any subsequent link. We use the Env_Ids map to check which
         --  envs we have already seen or not.
         if not Env_Ids.Contains (Current.Self_Env) then
            Env := Current.Self_Env;
            Put ("<" & Kind_Name (Current) & " "
                 & Image (Sloc_Range (Current)) & "> - ");
            Dump_One_Lexical_Env
              (Env, Get_Env_Id (Env), Get_Env_Id (Env.Parent));
         end if;

         for Child of ${root_node_type_name}_Arrays.Array_Type'
            (Children (Current))
         loop
            Internal (Child);
         end loop;
      end Internal;
      --  This procedure implements the main recursive logic of dumping the
      --  environments.
   begin
      Internal (${root_node_type_name} (Node));
   end Dump_Lexical_Env;

   -------------
   -- Parents --
   -------------

   function Parents
     (Node         : access ${root_node_value_type}'Class;
      Include_Self : Boolean := True)
      return ${root_node_array.name()}
   is
      Count : Natural := 0;
      Start : ${root_node_type_name} :=
        ${root_node_type_name} (if Include_Self then Node else Node.Parent);
      Cur   : ${root_node_type_name} := Start;
   begin
      while Cur /= null loop
         Count := Count + 1;
         Cur := Cur.Parent;
      end loop;

      declare
         Result : constant ${root_node_array.name()} := Create (Count);
      begin
         Cur := Start;
         for I in Result.Items'Range loop
            Result.Items (I) := Cur;
            Cur := Cur.Parent;
         end loop;
         return Result;
      end;
   end Parents;

   ------------
   -- Parent --
   ------------

   function Parent
     (Node : access ${root_node_value_type}'Class) return ${root_node_type_name}
   is
   begin
      return Node.Parent;
   end Parent;

   -------------
   -- Iterate --
   -------------

   function Iterate
     (Node : ${root_node_value_type})
      return
      ${root_node_type_name}_Ada2012_Iterators.Reversible_Iterator'Class
   is
   begin
      return It : constant Iterator := (Node => Node'Unrestricted_Access)
      do
         null;
      end return;
   end Iterate;

   -----------
   -- First --
   -----------

   overriding
   function First (Object : Iterator) return Children_Cursor is
      Node : ${root_node_type_name} renames Object.Node;
   begin
      return (if Node.Child_Count > 0
              then (Node, 1)
              else No_Children);
   end First;

   ----------
   -- Last --
   ----------

   overriding
   function Last (Object : Iterator) return Children_Cursor is
      Node : ${root_node_type_name} renames Object.Node;
   begin
      return (if Node.Child_Count > 0
              then (Node, Node.Child_Count)
              else No_Children);
   end Last;

   ----------
   -- Next --
   ----------

   overriding
   function Next
     (Object : Iterator;
      C      : Children_Cursor)
      return Children_Cursor
   is
      Node : ${root_node_type_name} renames Object.Node;
   begin
      if C = No_Children or else C.Child_Index >= Node.Child_Count then
         return No_Children;
      else
         return (Node, C.Child_Index + 1);
      end if;
   end Next;

   --------------
   -- Previous --
   --------------

   overriding
   function Previous
     (Object : Iterator;
      C      : Children_Cursor)
      return Children_Cursor
   is
      pragma Unreferenced (Object);
   begin
      if C = No_Children or else C.Child_Index <= 1 then
         return No_Children;
      else
         return (C.Node, C.Child_Index - 1);
      end if;
   end Previous;

   ------------------
   -- Child_Number --
   ------------------

   function Child_Number
     (Node : access ${root_node_value_type}'Class)
      return Positive
   is
      N : ${root_node_type_name} := null;
   begin
      for I in Node.Parent.First_Child_Index .. Node.Parent.Last_Child_Index
      loop
         N := Child (Node.Parent, I);
         if N = Node then
            return I;
         end if;
      end loop;

      --  If we reach this point, then Node isn't a Child of Node.Parent. This
      --  is not supposed to happen.
      raise Program_Error;
   end Child_Number;

   ----------------------
   -- Previous_Sibling --
   ----------------------

   function Previous_Sibling
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_type_name}
   is
      N : constant Positive := Child_Number (Node);
   begin
      return (if N = 1
              then null
              else Node.Parent.Child (N - 1));
   end Previous_Sibling;

   ------------------
   -- Next_Sibling --
   ------------------

   function Next_Sibling
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_type_name}
   is
   begin
      --  If Node is the last sibling, then Child will return null
      return Node.Parent.Child (Child_Number (Node) + 1);
   end Next_Sibling;

   % if ctx.env_metadata:
   ${struct_types.body(ctx.env_metadata)}

   -------------
   -- Combine --
   -------------

   function Combine
     (L, R : ${ctx.env_metadata.name()}) return ${ctx.env_metadata.name()}
   is
      % if not ctx.env_metadata.get_fields():
      pragma Unreferenced (L, R);
      % endif
      Ret : ${ctx.env_metadata.name()} := (others => False);
   begin
      % for field in ctx.env_metadata.get_fields():
         Ret.${field.name} := L.${field.name} or R.${field.name};
      % endfor
      return Ret;
   end Combine;

   % endif

   ---------
   -- Get --
   ---------

   function Get
     (A     : AST_Envs.Env_Element_Array;
      Index : Integer)
      return Env_Element
   is
      function Length (A : AST_Envs.Env_Element_Array) return Natural
      is (A'Length);

      function Get
        (A     : AST_Envs.Env_Element_Array;
         Index : Integer)
         return Env_Element
      is (A (Index + 1)); --  A is 1-based but Index is 0-based

      function Relative_Get is new Langkit_Support.Relative_Get
        (Item_Type     => Env_Element,
         Sequence_Type => AST_Envs.Env_Element_Array,
         Length        => Length,
         Get           => Get);
      Result : Env_Element;
   begin
      if Relative_Get (A, Index, Result) then
         return Result;
      else
         raise Property_Error with "out-of-bounds array access";
      end if;
   end Get;

   ## Generate the bodies of the root grammar class properties
   % for prop in T.root_node.get_properties(include_inherited=False):
   ${prop.prop_def}
   % endfor

   --------------------------------
   -- Assign_Names_To_Logic_Vars --
   --------------------------------

   procedure Assign_Names_To_Logic_Vars
    (Node : access ${root_node_value_type}'Class) is
   begin
      if Adalog.Debug.Debug then
         % for f in T.root_node.get_fields( \
              include_inherited=False, \
              predicate=lambda f: is_logic_var(f.type) \
         ):
            Node.${f.name}.Dbg_Name :=
              new String'(Image (Node.Short_Image) & ".${f.name}");
         % endfor
         for Child of ${root_node_type_name}_Arrays.Array_Type'
            (Children (Node))
         loop
            if Child /= null then
               Assign_Names_To_Logic_Vars (Child);
            end if;
         end loop;
      end if;
   end Assign_Names_To_Logic_Vars;

end ${_self.ada_api_settings.lib_name}.AST;

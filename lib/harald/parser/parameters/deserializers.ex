defmodule Harald.Parser.Parameters.Deserializers do
  @moduledoc """

  """

  alias Harald.Parser.{Ast, Parameters, Parameters.BinPiece}

  def parse_param(context) do
    update_in(context, [:target, :deserializers], fn [acc_head | acc_tail] ->
      head = izer_chunks(context.target.parameter.partial, acc_head, context)
      [head | acc_tail]
    end)
  end

  def ast(:generic_access_profile, name, prefix) do
    parameter = {:generic_access_profile, {:<<>>, [], prefix}}

    [
      quote context: Elixir do
        def deserialize(unquote(parameter)) do
          %{type: :generic_access_profile, id: unquote(name)}
        end
      end
    ]
  end

  def ast(:return, name, prefix) do
    parameter = {{:return, name}, {:<<>>, [], prefix}}

    [
      quote context: Elixir do
        def deserialize(unquote(parameter)) do
          %{type: :return, opcode: unquote(name)}
        end
      end
    ]
  end

  def ast(:command, name, prefix) do
    [
      quote context: Elixir do
        def deserialize(unquote({:<<>>, [], prefix ++ [0]})) do
          %{type: :command, opcode: unquote(name)}
        end
      end
    ]
  end

  def ast(:event, name, prefix) do
    parameter = {:<<>>, [], prefix ++ [Ast.var(:_parameter_total_length)]}

    [
      quote context: Elixir do
        def deserialize(unquote(parameter)) do
          %{type: :event, event_code: unquote(name)}
        end
      end
    ]
  end

  def ast(:subevent, {event_name, _}, prefix) do
    parameter = {:<<>>, [], prefix ++ [Ast.var(:_parameter_total_length)]}

    [
      quote context: Elixir do
        def deserialize(unquote(parameter)) do
          %{type: :event, event_code: unquote(event_name)}
        end
      end
    ]
  end

  defp izer_chunks(param, acc_izer, context)

  defp izer_chunks(%{type: _type} = param, acc_izer, context) do
    bin_pieces = BinPiece.from_param(param, context)
    transforms = transforms(param, context)
    keys = map_key(param, context)
    concat(context.target.spec_type, acc_izer, {bin_pieces, transforms, keys})
  end

  defp transforms(param, context)

  defp transforms(%{type: :error_code}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        unquote(parameter_var) = Harald.HCI.error_desc(unquote(parameter_var))
      end
    ]
  end

  defp transforms(%{type: :command_return}, context) do
    parameter_var = context.target.parameter.var
    command_opcode = Parameters.relative_parameter(-1, context)

    [
      quote context: Elixir do
        unquote(parameter_var) =
          Harald.HCI.deserialize({{:return, unquote(command_opcode)}, unquote(parameter_var)})
      end
    ]
  end

  defp transforms(%{type: :null_terminated}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        [head | tail] = String.split(unquote(parameter_var), <<0>>)
      end,
      quote context: Elixir do
        unquote(parameter_var) = {head, Enum.join(tail)}
      end
    ]
  end

  defp transforms(%{type: :opcode}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        unquote(parameter_var) = Harald.HCI.command_name(unquote(parameter_var))
      end
    ]
  end

  defp transforms(%{type: :arrayed_data} = param, context) do
    schema =
      param.parameters
      |> Harald.HCI.ArrayedData.schema_from_spec_parameters()
      |> Macro.escape()

    parameter_var = context.target.parameter.var
    p1 = Parameters.relative_parameter(-(length(param.parameters) + 1), context)

    [
      quote context: Elixir do
        {_, unquote(parameter_var)} =
          Harald.HCI.ArrayedData.deserialize(
            unquote(schema),
            unquote(p1),
            unquote(parameter_var)
          )
      end
    ]
  end

  defp transforms(_, _), do: []

  defp map_key(%{type: :subevent_code} = param, context) do
    name = param.name
    subevent_name = context.target.partial.name

    [
      quote context: Elixir do
        {unquote(name), unquote(subevent_name)}
      end
    ]
  end

  defp map_key(%{value: value} = param, context), do: [{param.name, value}]

  defp map_key(param, context), do: [{param.name, context.target.parameter.var}]

  defp concat(spec_type, ast, {bin_pieces, transforms, keys})
       when spec_type in [:command, :event, :subevent] do
    ast
    |> List.wrap()
    |> Enum.map(fn
      {:def, m1, [{:deserialize, m2, [{:<<>>, [], bin_args}]}, [do: acc_do_value]]} ->
        do_value = Ast.concat_do_value(acc_do_value, transforms, keys)
        bin_ast = {:<<>>, [], bin_args ++ bin_pieces}

        {:def, m1,
         [
           {:deserialize, m2, [bin_ast]},
           [do: do_value]
         ]}
    end)
  end

  defp concat(spec_type, ast, {bin_pieces, transforms, keys})
       when spec_type in [:return, :generic_access_profile] do
    ast
    |> List.wrap()
    |> Enum.map(fn
      {:def, m1, [{:deserialize, m2, [{name, {:<<>>, [], bin_args}}]}, [do: acc_do_value]]} ->
        do_value = Ast.concat_do_value(acc_do_value, transforms, keys)
        bin_ast = {:<<>>, [], bin_args ++ bin_pieces}

        {:def, m1,
         [
           {:deserialize, m2, [{name, bin_ast}]},
           [do: do_value]
         ]}
    end)
  end
end

defmodule Harald.Parser.Parameters.Serializers do
  @moduledoc """

  """

  alias Harald.Parser.{Ast, Parameters, Parameters.BinPiece}

  def parse_param(context) do
    update_in(context, [:target, :serializers], fn [acc_head | acc_tail] ->
      head = izer_chunks(context.target.parameter.partial, acc_head, context)
      [head | acc_tail]
    end)
  end

  def ast(:command, name, prefix) do
    [
      quote context: Elixir do
        def serialize(%{opcode: unquote(name), type: :command}) do
          unquote({:<<>>, [], prefix ++ [0]})
        end
      end
    ]
  end

  def ast(:return, name, _) do
    [
      quote context: Elixir do
        def serialize(%{opcode: unquote(name), type: :return}) do
          <<>>
        end
      end
    ]
  end

  def ast(:generic_access_profile, name, _) do
    [
      quote context: Elixir do
        def serialize(%{id: unquote(name), type: :generic_access_profile}) do
          <<>>
        end
      end
    ]
  end

  def ast(:event, name, prefix) do
    return =
      {:<<>>, [],
       prefix ++
         [
           Ast.var(:parameter_total_length),
           {:"::", [], [Ast.var(:parameters), Ast.var(:binary)]}
         ]}

    [
      quote context: Elixir do
        def serialize(%{event_code: unquote(name), type: :event}) do
          parameters = <<>>
          parameter_total_length = byte_size(parameters)
          unquote(return)
        end
      end
    ]
  end

  def ast(:subevent, {event_name, _}, prefix) do
    return =
      {:<<>>, [],
       prefix ++
         [
           Ast.var(:parameter_total_length),
           {:"::", [], [Ast.var(:parameters), Ast.var(:binary)]}
         ]}

    [
      quote context: Elixir do
        def serialize(%{
              event_code: unquote(event_name),
              type: :event
            }) do
          parameters = <<>>
          parameter_total_length = byte_size(parameters)
          unquote(return)
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

  defp transforms(%{type: :boolean}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        unquote(parameter_var) = Harald.HCI.serialize({:boolean, unquote(parameter_var)})
      end
    ]
  end

  defp transforms(%{type: :error_code}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        unquote(parameter_var) = Harald.HCI.error_code(unquote(parameter_var))
      end
    ]
  end

  defp transforms(%{type: :command_return}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        unquote(parameter_var) = Harald.HCI.serialize(unquote(parameter_var))
      end
    ]
  end

  defp transforms(%{type: :null_terminated}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        unquote(parameter_var) =
          elem(unquote(parameter_var), 0) <> <<0>> <> elem(unquote(parameter_var), 1)
      end
    ]
  end

  defp transforms(%{type: :opcode}, context) do
    parameter_var = context.target.parameter.var

    [
      quote context: Elixir do
        unquote(parameter_var) = Harald.HCI.command_opcode(unquote(parameter_var))
      end
    ]
  end

  defp transforms(%{type: :arrayed_data} = param, context) do
    schema =
      param.parameters
      |> Harald.HCI.ArrayedData.schema_from_spec_parameters()
      |> Macro.escape()

    parameter_var = context.target.parameter.var
    under_var = Ast.var(:_)

    [
      quote context: Elixir do
        {unquote(under_var), unquote(parameter_var)} =
          Harald.HCI.ArrayedData.serialize(unquote(schema), unquote(parameter_var))
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

  defp concat(spec_type, ast, {new_bin_args, transforms, keys})
       when spec_type in [:event, :subevent] do
    ast
    |> List.wrap()
    |> Enum.map(fn
      {:def, m1,
       [{:serialize, m2, [{:%{}, [], map_args}]}, [{:do, {:__block__, _, acc_block_args}}]]} ->
        do_value = concat_event_do_value(new_bin_args, transforms, acc_block_args)

        {:def, m1,
         [
           {:serialize, m2, [{:%{}, [], map_args ++ keys}]},
           [{:do, do_value}]
         ]}
    end)
  end

  defp concat(spec_type, ast, {bin_pieces, transforms, keys})
       when spec_type in [:command, :return, :generic_access_profile] do
    ast
    |> List.wrap()
    |> Enum.map(fn
      {:def, m1, [{:serialize, m2, [{:%{}, [], map_args}]}, [{:do, acc_do_value}]]} ->
        do_value = Ast.concat_do_value(acc_do_value, transforms, bin_pieces)

        {:def, m1,
         [
           {:serialize, m2, [{:%{}, [], map_args ++ keys}]},
           [{:do, do_value}]
         ]}
    end)
  end

  defp concat_event_do_value(new_bin_args, transforms, acc_block_args) do
    {acc_transforms,
     [
       {:=, [], [parameters_var, {:<<>>, [], acc_bin_args}]},
       parameter_total_length,
       ret_bin
     ]} = Enum.split(acc_block_args, -3)

    bin_args = acc_bin_args ++ new_bin_args

    {:__block__, [],
     acc_transforms ++
       transforms ++
       [
         {:=, [], [parameters_var, {:<<>>, [], bin_args}]},
         parameter_total_length,
         ret_bin
       ]}
  end
end

defmodule Harald.Parser.GenClause do
  alias Harald.Parser.Parameters

  def from_param(param, state)

  def from_param(%{value: _}, _), do: []

  def from_param(%{size: size, type: {:list, sub_type_id}}, state) when is_binary(size) do
    name = state.ast_map.parameter_var
    length_data = Parameters.parameter_var("Length_Data", state)

    [
      quote do
        unquote(name) <- StreamData.list_of(Harald.Generators.HCI.generate(unquote(sub_type_id)))
      end,
      quote do
        unquote(name) = Enum.join(List.flatten(unquote(name)))
      end,
      quote do
        unquote(length_data) = byte_size(unquote(name))
      end
    ]
  end

  def from_param(%{type: :arrayed_data} = param, state) do
    name = state.ast_map.parameter_var
    count = Parameters.relative_parameter(-(length(param.parameters) + 1), state)
    state = put_in(state, [:ast_map, :arrayed_data], true)

    {clauses, offset, params, state} =
      Enum.reduce(param.parameters, {[], length(param.parameters), [], state}, fn
        sub_param, {acc_clauses, offset, params, state} ->
          rel_param = Parameters.relative_parameter(-offset, state)
          state = put_in(state, [:ast_map, :parameter_var], rel_param)

          clauses =
            case from_param(sub_param, state) do
              [
                {:=, _,
                 [
                   name,
                   {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :map]}, [], _} = clause
                 ]}
              ] = clauses ->
                clauses

              [{:<-, _, [name, clause]} | clauses] ->
                [
                  quote do
                    unquote(name) <- StreamData.list_of(unquote(clause), length: unquote(count))
                  end
                  | clauses
                ]
            end

          {acc_clauses ++ clauses, offset - 1, params ++ [rel_param], state}
      end)

    clauses
    |> List.flatten()
    |> Enum.concat([
      quote do
        unquote(name) = IO.iodata_to_binary(List.flatten([unquote_splicing(params)]))
      end
    ])
  end

  def from_param(%{size: size, type: :binary}, state) do
    name = state.ast_map.parameter_var

    cond do
      is_binary(size) ->
        index = Parameters.parameter_index(size, state)
        size = Parameters.parameter_var(index)
        offset = state.ast_map.parameter_index - index - 1

        [
          quote do
            unquote(name) <- StreamData.binary(length: unquote(size) - unquote(offset))
          end
        ]

      true ->
        [
          quote do
            unquote(name) <- StreamData.bitstring(length: unquote(size))
          end
        ]
    end
  end

  def from_param(%{type: :command_return}, state) do
    opcode = Parameters.relative_parameter(-1, state)
    name = state.ast_map.parameter_var

    [
      quote do
        unquote(name) <-
          Harald.Generators.HCI.generate({:return, Harald.HCI.command_name(unquote(opcode))})
      end
    ]
  end

  def from_param(%{values: %{} = values}, state) do
    name = state.ast_map.parameter_var
    values = Macro.escape(values)

    [
      quote do
        unquote(name) <- StreamData.member_of(unquote(values))
      end
    ]
  end

  def from_param(%{values: values}, state) do
    name = state.ast_map.parameter_var

    [
      quote do
        unquote(name) <- StreamData.member_of(unquote(values))
      end
    ]
  end

  def from_param(%{type: :integer} = param, state) do
    name = state.ast_map.parameter_var

    [
      quote do
        unquote(name) <- StreamData.integer(0..255)
      end
    ]
  end

  def from_param(%{type: :error_code}, state) do
    error_codes = state.types.error_codes.values
    name = state.ast_map.parameter_var

    [
      quote do
        unquote(name) <- StreamData.member_of(unquote(error_codes))
      end
    ]
  end

  def from_param(%{type: :null_terminated} = param, state) do
    size = div(param.size, 8)
    name = state.ast_map.parameter_var

    [
      quote do
        unquote(name) <- Harald.Generators.HCI.generate(:null_terminated, length: unquote(size))
      end
    ]
  end
end

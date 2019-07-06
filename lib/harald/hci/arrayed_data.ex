defmodule Harald.HCI.ArrayedData do
  @moduledoc """
  Serialization functions for arrayed data.

  > Arrayed parameters are specified using the following notation: ParameterA[i]. If more than one
  > set of arrayed parameters are specified (e.g. ParameterA[i], ParameterB[i]), then, unless
  > noted otherwise, the order of the parameters are as follows: ParameterA[0], ParameterB[0],
  > ParameterA[1], ParameterB[1], ParameterA[2], ParameterB[2], ... ParameterA[n], ParameterB[n]

  Reference: Version 5.0, Vol 2, Part E, 5.2

  Both `serialize/2` and `deserialize/4` rely on a schema to function. A schema is a keyword list
  where each key is a field and each value shall be:

  - a positive integer when denoting the size in bits of the field
  - a three-tuple when the field itself represents the length of a subsequent variable length
    field
  - an atom when the field is variable length and a preceding field represents its length

  For example if `length_data` itself was 8 bits and represented the length of `data` that would
  be written as:

  ```
  [
    length_data: {:variable, :data, 8},
    data: :length_data
  ]
  ```
  """

  @type field :: atom()

  @type field_size ::
          pos_integer()
          | {:variable, atom(), pos_integer()}
          | atom()

  @type schema :: [{field(), field_size()}, ...]

  @doc """
  Deserializes the binary representation of a list of structs according to `schema`.
  """
  def deserialize(schema, length, bin)

  def deserialize(_, length, <<>> = bin) when is_integer(length) and length > 0, do: {:error, bin}

  def deserialize(schema, length, bin) when is_integer(length) do
    schema
    |> deserialize(bin, %{
      data: init_data(length, %{}),
      field: nil,
      field_size: nil,
      field_type: nil,
      index: 1,
      length: length,
      variable: %{}
    })
    |> case do
      {:ok, _} = ret -> ret
      {:error, :incomplete} -> {:error, bin}
    end
  end

  # pull a tuple off the schema - recursion base case
  def deserialize([], _bin, %{field: nil} = state) do
    {:ok, for(index <- 1..state.length, do: state.data[index])}
  end

  # pull a tuple off the schema - defining variable lengths
  def deserialize([{field, {:variable, _, _} = field_size} | schema], bin, %{field: nil} = state) do
    variable = Map.put(state.variable, field, [])
    deserialize(schema, bin, %{state | field: field, field_size: field_size, variable: variable})
  end

  # pull a tuple off the schema
  def deserialize([{field, field_size} | schema], bin, %{field: nil} = state) do
    deserialize(schema, bin, %{state | field: field, field_size: field_size})
  end

  # pull a tuple off the schema
  def deserialize([{field, field_size, field_type} | schema], bin, %{field: nil} = state) do
    deserialize(schema, bin, %{
      state
      | field: field,
        field_size: field_size,
        field_type: field_type
    })
  end

  # pull data off the binary - reading variable lengths
  def deserialize(
        _schema,
        <<>>,
        %{field_size: {:variable, _, _field_size}, index: index, length: length}
      )
      when index <= length do
    {:error, :incomplete}
  end

  # pull data off the binary - reading variable lengths
  def deserialize(
        schema,
        bin,
        %{field_size: {:variable, _, field_size}, index: index, length: length} = state
      )
      when index <= length do
    <<parameter::little-size(field_size), bin::binary>> = bin
    variable = Map.update!(state.variable, state.field, &[parameter | &1])
    deserialize(schema, bin, %{state | index: index + 1, variable: variable})
  end

  # pull data off the binary - reading variable length targets
  def deserialize(schema, bin, %{field_size: variable_key, index: index, length: length} = state)
      when index <= length and is_binary(variable_key) do
    {field_size, variable} =
      Map.get_and_update!(state.variable, variable_key, fn [field_size | rest] ->
        {field_size, rest}
      end)

    case bin do
      <<parameter::binary-size(field_size), bin::binary>> ->
        parameter =
          case state.field_type do
            nil ->
              parameter

            {:list, :generic_access_profile} = type ->
              Harald.HCI.split_map(
                parameter,
                fn length, data ->
                  Harald.deserialize({:generic_access_profile, <<length, data::binary>>})
                end
              )
          end

        data = Map.update!(state.data, index, &Map.put(&1, state.field, parameter))
        deserialize(schema, bin, %{state | data: data, index: index + 1, variable: variable})

      _ ->
        {:error, :incomplete}
    end
  end

  # pull data off the binary
  def deserialize(schema, bin, %{field_size: field_size, index: index, length: length} = state)
      when index <= length do
    case bin do
      <<parameter::little-size(field_size), bin::binary>> ->
        data = Map.update!(state.data, index, &Map.put(&1, state.field, parameter))
        deserialize(schema, bin, %{state | data: data, index: index + 1})

      _ ->
        {:error, :incomplete}
    end
  end

  # field completed - defining variable lengths
  def deserialize(schema, bin, %{field_size: {:variable, _, _}} = state) do
    variable = Map.update!(state.variable, state.field, &Enum.reverse(&1))

    deserialize(schema, bin, %{
      state
      | field: nil,
        field_size: nil,
        field_type: nil,
        index: 1,
        variable: variable
    })
  end

  # field completed
  def deserialize(schema, bin, state) do
    deserialize(schema, bin, %{state | field: nil, field_size: nil, field_type: nil, index: 1})
  end

  def schema_from_spec_parameters(parameters) do
    parameters
    |> Enum.reduce([], fn
      %{size: size, type: {:list, :generic_access_profile}} = param,
      [{prev_name, prev_size} | acc]
      when is_binary(size) ->
        [
          {param.name, size, {:list, :generic_access_profile}},
          {prev_name, {:variable, param.name, prev_size}} | acc
        ]

      %{size: size} = param, [{prev_name, prev_size} | acc] when is_binary(size) ->
        [{param.name, size}, {prev_name, {:variable, param.name, prev_size}} | acc]

      param, acc ->
        [{param.name, param.size} | acc]
    end)
    |> Enum.reverse()
  end

  @doc """
  Serializes a list of `structs` into their binary representation according to `schema`.
  """
  def serialize(schema, maps) do
    data =
      maps
      |> Enum.with_index()
      |> Map.new(fn {map, index} -> {index + 1, map} end)

    length = length(maps)

    serialize(schema, <<>>, %{
      data: data,
      field: nil,
      field_type: nil,
      field_size: nil,
      index: 1,
      length: length
    })
  end

  # pull a tuple off the schema - recursion base case
  defp serialize([], bin, %{field: nil}), do: {:ok, bin}

  # pull a tuple off the schema - defining variable lengths
  defp serialize([{field, {:variable, _, _} = field_size} | schema], bin, %{field: nil} = state) do
    serialize(schema, bin, %{state | field: field, field_size: field_size})
  end

  # pull a tuple off the schema
  defp serialize([{field, field_size} | schema], bin, %{field: nil} = state) do
    serialize(schema, bin, %{state | field: field, field_size: field_size})
  end

  # pull a tuple off the schema
  defp serialize([{field, field_size, field_type} | schema], bin, %{field: nil} = state) do
    serialize(schema, bin, %{state | field: field, field_size: field_size, field_type: field_type})
  end

  # put data on the binary - writing variable lengths
  defp serialize(
         schema,
         bin,
         %{field_size: {:variable, field_target, field_size}, index: index, length: length} =
           state
       )
       when index <= length do
    field = state.field

    field_type =
      Enum.reduce_while(schema, false, fn
        {{^field, _}, _} ->
          {:cont, true}

        {{_, _, {:list, sub_type_id}}, true} ->
          Harald.HCI.join_map(Map.fetch!(state.data[index], field_target), fn data ->
            Harald.serialize(data)
          end)

        acc ->
          {:cont, acc}
      end)

    target =
      case field_type do
        nil ->
          Map.fetch!(state.data[index], field_target)

        {:list, :generic_access_profile} ->
          nil
      end

    target_length = byte_size(target)
    bin = <<bin::binary, target_length::little-size(field_size)>>
    serialize(schema, bin, %{state | index: index + 1})
  end

  # put data on the binary - writing variable length targets
  defp serialize(schema, bin, %{field_size: variable_key, index: index, length: length} = state)
       when index <= length and is_binary(variable_key) do
    tail =
      case state.field_type do
        nil ->
          Map.fetch!(state.data[index], state.field)

        {:list, :generic_access_profile} ->
          Harald.HCI.join_map(Map.fetch!(state.data[index], state.field), fn data ->
            Harald.serialize(data)
          end)
      end

    bin = <<bin::binary, tail::binary>>
    serialize(schema, bin, %{state | index: index + 1})
  end

  # put data on the binary
  defp serialize(schema, bin, %{field_size: field_size, index: index, length: length} = state)
       when index <= length do
    bin =
      <<bin::binary, Map.fetch!(state.data[index], state.field)::integer-little-size(field_size)>>

    serialize(schema, bin, %{state | index: index + 1})
  end

  # field completed
  defp serialize(schema, bin, state) do
    serialize(schema, bin, %{state | field: nil, field_size: nil, index: 1})
  end

  defp init_data(length, value) do
    Enum.reduce(1..length, %{}, fn index, acc -> Map.put(acc, index, value) end)
  end
end

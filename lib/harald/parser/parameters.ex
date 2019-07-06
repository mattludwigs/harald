defmodule Harald.Parser.Parameters do
  @moduledoc """

  """

  alias Harald.Parser.{Ast, Context}
  alias Harald.Parser.Parameters.{Deserializers, Serializers}

  def parse(context) do
    context = put_in(context, [:target, :parameter], Context.parameter())

    context.target.partial.parameters
    |> Enum.reduce(context, fn
      param, context ->
        context
        |> put_in([:target, :parameter, :partial], param)
        |> expand_parameter(param)
        |> Serializers.parse_param()
        |> Deserializers.parse_param()
        |> increment_param_index(param)
    end)
    |> parameters_finish()
  end

  def parameter_index(name, state) do
    state.target.processed_parameters
    |> Enum.reverse()
    |> Enum.find_index(fn x -> x.name == name end)
  end

  def relative_parameter(offset, state) do
    "v#{state.target.parameter.index + offset}"
    |> String.to_atom()
    |> Ast.var()
  end

  def expand_parameter(context, %{type: :arrayed_data} = param) do
    Enum.reduce(param.parameters, context, fn sub_param, context ->
      context
      |> expand_parameter(sub_param)
      |> increment_param_index(sub_param)
    end)
  end

  def expand_parameter(context, param) do
    type_id = type_id(param)
    type = Map.fetch!(context.types, type_id)
    type_size = Map.get(type, :size, 8)

    param =
      %{type: type_id, size: type_size}
      |> Map.merge(param)
      |> default_values(type)

    case context.target.parameter.partial[:type] do
      :arrayed_data -> put_arrayed_param(context, param)
      _ -> put_in(context, [:target, :parameter, :partial], param)
    end
  end

  defp put_arrayed_param(context, param) do
    name = param.name

    update_in(context, [:target, :parameter, :partial, :parameters], fn parameters ->
      Enum.map(parameters, fn
        %{name: ^name} -> param
        x -> x
      end)
    end)
  end

  def parameter_var(name, context) when is_binary(name) do
    name
    |> parameter_index(context)
    |> case do
      x when is_integer(x) ->
        parameter_var(context.target.parameter.index - x - 1)

      x ->
        raise "failed to find param #{name} in #{inspect(context.target.processed_parameters)}"
    end
  end

  def parameter_var(index) do
    "v#{index}"
    |> String.to_atom()
    |> Ast.var()
  end

  defp default_values(param, type) do
    case Map.fetch(type, :values) do
      {:ok, values} -> Map.put_new(param, :values, values)
      _ -> param
    end
  end

  defp type_id(param) do
    case Map.get(param, :type) do
      nil -> :integer
      {:list, _} -> :list
      type_id -> type_id
    end
  end

  defp increment_param_index(context, param) do
    Map.update!(context, :target, fn target ->
      incremented_index = target.parameter.index + 1
      parameter_var = parameter_var(incremented_index)

      target
      |> Map.update!(:parameter, fn parameter ->
        Map.merge(parameter, %{index: incremented_index, var: parameter_var})
      end)
      |> Map.update!(:processed_parameters, &Enum.concat(&1, [param]))
    end)
  end

  defp parameters_finish(context) do
    context
    |> update_in([:target, :deserializers], &List.flatten/1)
    |> update_in([:target, :serializers], &List.flatten/1)
    |> Map.update!(:ast_maps, &[context.target | &1])
    |> Map.put(:target, nil)
  end
end

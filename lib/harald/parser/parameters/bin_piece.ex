defmodule Harald.Parser.Parameters.BinPiece do
  alias Harald.Parser.{Ast, Parameters}

  def from_param(%{type: :opcode}, context) do
    parameter_var = context.target.parameter.var

    quote context: Elixir do
      <<unquote(parameter_var)::binary-size(2)>>
    end
    |> elem(2)
  end

  def from_param(%{value: value}, _), do: [value]

  def from_param(%{type: type} = tee, context)
      when type in [:arrayed_data, :command_return, :binary] do
    # TODO use quote
    [{:"::", [], [context.target.parameter.var, Ast.var(:binary)]}]
  end

  def from_param(%{size: size} = param, context) when is_atom(size) do
    from_param(%{param | size: context.target.parameter.var}, context)
  end

  def from_param(%{size: size} = param, context) when is_binary(size) do
    size = Parameters.parameter().var(size, context)
    from_param(%{param | size: size}, context)
  end

  def from_param(%{type: :null_terminated} = param, context) do
    parameter_var = context.target.parameter.var
    size = div(param.size, 8)

    quote context: Elixir do
      <<unquote(parameter_var)::binary-size(unquote(size))>>
    end
    |> elem(2)
  end

  def from_param(%{size: 8, type: :error_code} = tee, context) do
    [context.target.parameter.var]
  end

  def from_param(%{size: size, type: _type} = tee, context) do
    [{:"::", [], [context.target.parameter.var, {:size, [], [size]}]}]
  end
end

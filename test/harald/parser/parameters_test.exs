defmodule Harald.Parser.ParametersTest do
  use ExUnit.Case, async: true
  alias Harald.Spec
  alias Harald.Parser.{Context, Parameters}

  doctest Parameters, import: true

  # test "expand_parameter/1" do
  #   context = Context.new(Spec.definition(:v5_1))
  #   param = %{}
  #   assert %{} = Parameters.expand_parameter(context, param)
  # end
end

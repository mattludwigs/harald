defmodule Harald.Parser.MapKey do
  defp gen_body(%{value: value}, _) do
    [Macro.escape(value)]
  end

  defp gen_body(%{type: type}, state)
       when type in [:arrayed_data, :command_return, :null_terminated, :opcode, :binary] do
    var = state.ast_map.parameter_var

    [
      quote do
        unquote(var) :: binary
      end
    ]
  end

  defp gen_body(_, state), do: [state.ast_map.parameter_var]
end

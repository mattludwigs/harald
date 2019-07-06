defmodule Harald.Log do
  @moduledoc """
  Facilitates structured logging.
  """

  defmacro debug(description, {:%{}, _, _} = data) when is_binary(description) do
    quote bind_quoted: [data: data, description: description, module: __CALLER__.module] do
      require Logger

      %{
        module: module,
        description: description,
        data: data
      }
      |> Jason.encode()
      |> case do
        {:ok, structured_log} -> fn -> structured_log end
      end
      |> Logger.debug()
    end
  end
end

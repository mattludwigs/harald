defmodule Harald.Transport.Adapter do
  @moduledoc """
  A behaviour for transport adapters.
  """

  alias Harald.HCI

  @typedoc """
  The `args` in `start_link/1`.
  """
  @type start_link_args :: %{
          required(:namespace) => Harald.namespace(),
          optional(:module) => module(),
          optional(:parent_pid) => pid(),
          optional(:uart_opts) => [Circuits.UART.uart_option()]
        }

  @type state :: %{}

  @callback start_link(start_link_args()) :: {:ok, state()}
  @callback stop(Harald.namespace()) :: :ok
  @callback send_binary(HCI.command(), state()) ::
              {:ok, state()} | {:error, any()}
end

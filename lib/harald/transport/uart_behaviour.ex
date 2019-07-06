defmodule Harald.Transport.UARTBehaviour do
  @moduledoc false

  @callback start_link() :: {:ok, pid()}

  @callback open(GenServer.server(), binary(), [Circuits.UART.uart_option()]) ::
              :ok | {:error, term()}

  @callback write(GenServer.server(), binary()) :: :ok | {:error, term()}
end

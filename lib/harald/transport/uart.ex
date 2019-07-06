defmodule Harald.Transport.UART do
  @moduledoc """
  A UART transport.
  """

  use GenServer
  alias Harald.Transport.Adapter
  alias Harald.Transport.UART.Framing

  @typedoc """
  The `args` in `start_link/1`.
  """
  @type start_link_args :: %{
          required(:namespace) => Harald.namespace(),
          optional(:module) => module(),
          optional(:parent_pid) => pid(),
          optional(:uart_opts) => [Circuits.UART.uart_option()]
        }

  @type state :: %{adapter_pid: pid()}

  @behaviour Adapter

  @doc false
  def name(namespace) when is_atom(namespace) do
    String.to_atom("#{__MODULE__}.namespace.#{namespace}")
  end

  @impl Adapter
  @spec start_link(start_link_args()) :: {:ok, state()}
  def start_link(args) do
    args =
      DeepMerge.deep_merge(
        %{
          module: Circuits.UART,
          parent_pid: self(),
          uart_opts: [active: true, framing: {Framing, []}]
        },
        args
      )

    case GenServer.start_link(__MODULE__, args, name: name(args.namespace)) do
      {:ok, pid} -> {:ok, %{adapter_pid: pid}}
      {:error, _} = err -> err
    end
  end

  @impl Adapter
  def stop(namespace) when is_atom(namespace) do
    namespace
    |> name
    |> GenServer.stop()
  end

  @impl Adapter
  def send_binary(bin, %{adapter_pid: adapter_pid} = state) do
    :ok = GenServer.call(adapter_pid, {:send_binary, bin})
    {:ok, state}
  end

  @impl GenServer
  def init(%{device: _, module: module} = args) do
    {:ok, pid} = module.start_link()
    :ok = module.open(pid, args.device, args.uart_opts)
    {:ok, %{module: module, parent_pid: args.parent_pid, uart_pid: pid}}
  end

  @impl GenServer
  def handle_call({:send_binary, bin}, _from, state) do
    {:reply, state.module.write(state.uart_pid, bin), state}
  end

  @impl GenServer
  def handle_info({:circuits_uart, _dev, msg}, %{parent_pid: parent_pid} = state) do
    send(parent_pid, {:transport_adapter, msg})
    {:noreply, state}
  end
end

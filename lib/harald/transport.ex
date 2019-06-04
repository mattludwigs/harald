defmodule Harald.Transport do
  @moduledoc """
  A server to manage lower level transports and parse bluetooth events.
  """

  use GenServer
  alias Harald.HCI

  @type adapter_state :: map
  @type event :: struct() | binary()
  @type namespace :: atom
  @type handler_msg :: {:bluetooth_event, event()}

  defmodule State do
    @moduledoc false
    @enforce_keys [:adapter, :adapter_state, :handlers, :namespace]
    defstruct @enforce_keys
  end

  @doc """
  Start the transport.
  """
  @spec start_link(keyword) :: GenServer.server()
  def start_link(passed_args) do
    args = Keyword.put_new(passed_args, :handlers, default_handlers())

    GenServer.start_link(__MODULE__, args, name: name(args[:namespace]))
  end

  @impl GenServer
  def init(args) do
    {adapter, adapter_args} = Keyword.fetch!(args, :adapter)
    namespace = Keyword.fetch!(args, :namespace)
    {:ok, adapter_state} = apply(adapter, :setup, [self(), adapter_args])

    handlers =
      for h <- args[:handlers] do
        {:ok, pid} = apply(h, :setup, [[namespace: namespace]])
        pid
      end

    chip_opts = Keyword.get(args, :chip)

    state = %State{
      adapter: adapter,
      adapter_state: adapter_state,
      handlers: handlers,
      namespace: namespace
    }

    {:ok, state, {:continue, chip_opts}}
  end

  @doc """
  Makes a synchronous call to the configured transport adapter.
  """
  @spec call(namespace, binary()) :: any()
  def call(namespace, bin) when is_atom(namespace) and is_binary(bin) do
    namespace
    |> name()
    |> GenServer.call({:call, bin})
  end

  @doc """
  The default handlers that Transport will start.
  """
  @spec default_handlers() :: [Harald.LE, ...]
  def default_handlers, do: [Harald.LE]

  @impl GenServer
  def handle_continue(nil, state), do: {:noreply, state}

  def handle_continue({chip_mod, chip_args}, state) do
    {:ok, hci_commands} = chip_mod.setup(state.namespace, chip_args)

    adapter_state =
      Enum.reduce(hci_commands, state.adapter_state, fn bin, adapter_state ->
        {:ok, adapter_state} = state.adapter.call(bin, adapter_state)
        Process.sleep(50)
        adapter_state
      end)

    {:noreply, %State{state | adapter_state: adapter_state}}
  end

  @doc """
  Adds `pid` to the `namespace` transport's handlers.

  `pid` will receive messages like `t:handler_msg/0`.
  """
  def add_handler(namespace, pid) do
    namespace
    |> name()
    |> GenServer.call({:add_handler, pid})
  end

  @impl GenServer
  def handle_info({:transport_adapter, msg}, %{handlers: handlers} = state) do
    _ =
      msg
      |> HCI.deserialize()
      |> notify_handlers(handlers)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call(
        {:call, bin},
        _from,
        %State{adapter: adapter, adapter_state: adapter_state} = state
      ) do
    {:ok, adapter_state} = adapter.call(bin, adapter_state)
    {:reply, :ok, %State{state | adapter_state: adapter_state}}
  end

  @impl GenServer
  def handle_call({:add_handler, pid}, _from, state) do
    {:reply, :ok, %State{state | handlers: [pid | state.handlers]}}
  end

  defp name(namespace), do: String.to_atom("#{namespace}.#{__MODULE__}")

  defp notify_handlers({:ok, events}, handlers) when is_list(events) do
    for e <- events do
      for h <- handlers do
        send(h, {:bluetooth_event, e})
      end
    end
  end

  defp notify_handlers({:ok, event}, handlers), do: notify_handlers({:ok, [event]}, handlers)

  defp notify_handlers({:error, _} = error, handlers) do
    notify_handlers({:ok, [error]}, handlers)
  end
end

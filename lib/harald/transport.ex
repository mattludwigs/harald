defmodule Harald.Transport do
  @moduledoc """
  A server to manage lower level transports and parse bluetooth events.
  """

  use GenServer
  alias Harald.{HCI, Transport.UART}

  @typedoc """
  A list of `t:module()`s that implement the `Harald.Transport.Handler` behaviour. These modules
  will process Bluetooth events.
  """
  @type handlers :: [module()]

  @typedoc """
  A callback specification for the `:handle_start` option of `start_link/1`.

  Accepts a MFA or a function, but in either case they shouold return a `t:handle_start_ret()`.
  """
  @type handle_start :: {module(), atom(), list()} | (() -> handle_start_ret()) | nil

  @typedoc """
  The return value of a `handle_start/0`.
  """
  @type handle_start_ret :: {:ok, [HCI.command()]}

  @typedoc """
  The shape of the message a process will receive if it is a `Harald.Transport` handler.
  """
  @type handler_msg :: {:bluetooth_event, HCI.event()}

  @typedoc """
  The `args` in `start_link/1`.
  """
  @type start_link_args :: %{
          device: String.t(),
          namespace: Harald.namespace(),
          handle_start: handle_start(),
          handlers: handlers()
        }

  @doc """
  Start the transport.

  ## Args

  ### Required

    - `:namespace`, `t:namespace()`. Used to reference an instance of `Harald`.

  ### Optional

    - `:adapter` - `t:adapter()`, `%{args: %{namespace: namespace}, module:
      Harald.Transport.UART}`. Defines the adapter module and the args it will receive.
    - `:handle_start` - `t:handle_start()`, `nil`. A callback immediately after the transport
      starts, the callback shall return a `handle_start_ret()`. The returned HCI commands are
      executed immediately.
    - `:handlers`, `t:handlers()`, [] - A list of `t:module()`s that implement the
      `Harald.Transport.Handler` behaviour. These modules will process Bluetooth events.
  """
  @spec start_link(start_link_args()) :: GenServer.server()
  def start_link(%{device: _, namespace: namespace} = args) do
    args =
      DeepMerge.deep_merge(
        %{
          adapter: %{args: %{namespace: namespace}, module: UART},
          handle_start: nil,
          handlers: []
        },
        args
      )

    GenServer.start_link(__MODULE__, args, name: name(namespace))
  end

  @doc """
  Send a binary to the Bluetooth controller.
  """
  @spec send_binary(Harald.namespace(), HCI.command()) :: any()
  def send_binary(namespace, bin) when is_atom(namespace) and is_binary(bin) do
    namespace
    |> name()
    |> GenServer.call({:send_binary, bin})
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

  @doc false
  def name(namespace), do: String.to_atom("#{__MODULE__}.namespace.#{namespace}")

  @impl GenServer
  def init(%{adapter: adapter, namespace: namespace} = args) do
    adapter_args = Map.merge(%{parent_pid: self(), device: args.device}, adapter.args)
    {:ok, adapter_state} = adapter.module.start_link(adapter_args)
    handler_pids = setup_handlers(args.handlers, namespace)

    state = %{
      adapter: Map.put(adapter, :state, adapter_state),
      handlers: handler_pids,
      namespace: namespace
    }

    {:ok, state, {:continue, args.handle_start}}
  end

  @impl GenServer
  def handle_continue(nil, state), do: {:noreply, state}

  def handle_continue(handle_start, %{adapter: adapter} = state) do
    {:ok, hci_commands} = execute_handle_start(handle_start)
    adapter_state = send_binaries(hci_commands, adapter.module, adapter.state)
    {:noreply, %{state | adapter: %{adapter | state: adapter_state}}}
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
  def handle_call({:send_binary, bin}, _from, %{adapter: adapter} = state) do
    {:ok, adapter_state} = adapter.module.send_binary(bin, adapter.state)
    {:reply, :ok, %{state | adapter: %{adapter | state: adapter_state}}}
  end

  def handle_call({:add_handler, pid}, _from, state) do
    {:reply, :ok, %{state | handlers: [pid | state.handlers]}}
  end

  defp setup_handlers(handlers, namespace) do
    for h <- handlers do
      {:ok, pid} = h.setup(namespace: namespace)
      pid
    end
  end

  defp send_binaries(binaries, adapter_module, adapter_state) do
    Enum.reduce(binaries, adapter_state, fn bin, adapter_state ->
      {:ok, adapter_state} = adapter_module.send_binary(bin, adapter_state)
      adapter_state
    end)
  end

  defp execute_handle_start(handle_start) do
    case handle_start do
      {module, function, args} -> apply(module, function, args)
      function when is_function(function) -> function.()
    end
  end

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

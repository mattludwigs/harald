defmodule Harald do
  @moduledoc """
  An incomplete and opinionated abstraction over Bluetooth functionality.

  Bluetooth is exceptionally configurable and there are many ways to achieve similar outcomes. As
  such, leverage this module if convenient, otherwise interact with a `Harald.Transport` directly
  to send commands and react to events exactly as required to achieve the desired outcome.

  ## Initializing Harald

  Add `{Harald, args}` to a Supervisor's children. See `child_spec/1` for more info about `args`.
  """

  alias Harald.{HCI, Server, Transport}

  @type namespace :: atom()

  @type child_spec_args :: %{
          optional(:handle_start) => Transport.handle_start(),
          optional(:handlers) => Transport.handlers(),
          required(:namespace) => namespace()
        }

  @typedoc """
  A request is considered eroneous in these cases:

  - `:setup_incomplete` - The underlying `Harald.Transport` has not yet completed setting up the
    Bluetooth Controller.
  - `:already_scanning` - There is already a scan in progress.
  - `:command_complete_timeout` - A Command Complete event is not received in time.
  - A Command Complete event itself is the error reason when it includes a status parameter that
    could indicate success, but something other than success is indicated.
  """
  @type error_reason :: :timeout | :command_complete_timeout | %{event: :hci_command_complete}

  @typedoc """
  Tuple describing why a request was eroneous.
  """
  @type error :: {:error, error_reason()}

  @doc """
  Child specification that delegates to `Harald.Server`.

  ## Args

  ### Required

  `:namespace` - Uniquely identifies a particular instance of Harald.
  """
  @spec child_spec(child_spec_args()) :: Supervisor.child_spec()
  def child_spec(%{namespace: namespace} = args) do
    %{id: namespace, start: {Server, :start_link, [args]}}
  end

  @typedoc """
  The options accepted by `scan/2`.
  """
  @type scan_opts() :: [{:duration, non_neg_integer()}]

  @doc """
  Performs a scan for nearby devices.

  Though the time before this function returns is mostly dictated by the `:duration` option, it
  will not return until a Command Complete event is received for the command sent to stop
  scanning.

  ## Options

  - `:command_complete_timeout`, `t::pos_integer()`, `1_000` - The time in milliseconds after
    starting the scan that the scan should be stopped. The default choosen is informed by
    `Version 5.1, Vol 2, Part E, 5.1`.
  - `:duration` - The time in milliseconds after starting the scan that the scan should be
  """
  @spec scan(Transport.namespace(), scan_opts()) :: {:ok, []} | error()
  def scan(namespace, opts \\ []) do
    args =
      opts
      |> Enum.into(%{duration: 5_000, command_complete_timeout: 1_000})
      |> Map.take([:duration, :command_complete_timeout])

    timeout = args.duration + 5_000
    Server.call(namespace, {:scan, args}, timeout)
  end

  defdelegate deserialize(binary), to: HCI

  defdelegate serialize(map), to: HCI

  use ExUnitProperties

  def gen do
    gen all(
          bin <- StreamData.constant(<<4, 62>>),
          v2 <- StreamData.member_of(unquote(Macro.escape(1..1))),
          v3 <-
            StreamData.list_of(StreamData.member_of(unquote(Macro.escape(0..4))),
              length: v2
            ),
          v4 <-
            StreamData.list_of(StreamData.member_of(unquote(Macro.escape(0..3))),
              length: v2
            ),
          v5 <- StreamData.list_of(StreamData.binary(length: 48), length: v2),
          v6 <- StreamData.list_of(StreamData.integer(0..255), length: v2),
          v7 = Enum.map(v6, &Enum.at(StreamData.binary(length: &1), 0)),
          v8 <- StreamData.list_of(StreamData.integer(0..255), length: v2),
          v9 = IO.iodata_to_binary(List.flatten([v3, v4, v5, v6, v7, v8])),
          parameters = <<2, v2, v9::binary>>,
          parameter_total_length = byte_size(parameters)
        ) do
      <<bin::binary, parameter_total_length, parameters::binary>>
    end
  end
end

defmodule Harald.Server do
  @moduledoc """
  Safely manages the lifecycle of and interaction with a `Harald.Transport`.

  This module should not be interacted with directly, rather, leverage `Harald`.
  """

  use GenServer
  alias Harald.{HCI, Transport}
  require Harald.Log, as: Log

  @doc false
  def child_spec(_) do
    raise "Harald.Server should not be referenced directly in a Supervisor's children. See Harald.child_spec/1."
  end

  @doc false
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: name(args.namespace))
  end

  @impl GenServer
  def init(args) do
    {:ok, pid} = Transport.start_link(args)

    state = %{
      namespace: args.namespace,
      reports: %{},
      scan_from: nil
    }

    {:ok, state}
  end

  @doc false
  def call(namespace, request, timeout) do
    namespace
    |> name()
    |> GenServer.call(request, timeout)
  end

  @impl GenServer
  def handle_call({:scan, args}, from, %{scan_from: nil} = state) do
    {:ok, bin} =
      HCI.serialize(%{
        command: :hci_le_set_scan_enable,
        le_scan_enable: 1,
        filter_duplicates: 0
      })

    :ok = Transport.send_binary(state.namespace, bin)
    Process.send_after(self(), {:scan_stop, args}, args.duration)
    {:noreply, %{state | scan_from: from}}
  end

  def handle_call({:scan, _}, _, state), do: {:reply, {:error, :already_scanning}, state}

  @impl GenServer
  def handle_info({:scan_stop, args}, state) do
    {:ok, bin} =
      HCI.serialize(%{
        command: :hci_le_set_scan_enable,
        le_scan_enable: 0,
        filter_duplicates: 0
      })

    :ok = Transport.send_binary(state.namespace, bin)
    Process.send_after(self(), :command_complete, args.command_complete_timeout)
    {:noreply, state}
  end

  def handle_info(
        {:bluetooth_event,
         %{
           event: :hci_le_meta,
           subevent: %{event: :hci_le_advertising_report, reports: new_reports}
         }},
        state
      ) do
    reports =
      Enum.reduce(new_reports, state.reports, fn report, reports ->
        Map.put(reports, report.address, report)
      end)

    {:noreply, %{state | reports: reports}}
  end

  def handle_info(
        {:bluetooth_event,
         %{event: :hci_command_complete, return_parameters: %{status: "Success"}}},
        state
      ) do
    GenServer.reply(state.scan_from, state.devices)
    {:noreply, %{state | devices: %{}, scan_from: nil}}
  end

  def handle_info({:bluetooth_event, unhandled_bluetooth_event}, state) do
    Log.debug("unhandled bluetooth event", %{event: unhandled_bluetooth_event})
    {:noreply, state}
  end

  defp name(namespace), do: String.to_atom("#{__MODULE__}.namespace.#{namespace}")
end

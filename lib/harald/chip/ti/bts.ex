defmodule Harald.Chip.TI.BTS do
  @moduledoc """
  Parsing functionality for BTS files.

  Reference: http://www.ti.com/tool/WL18XX-BT-SP
  """

  require Logger

  @action_send_command 1

  @action_wait_event 2

  @action_serial 3

  @action_delay 4

  @action_run_script 5

  @action_remarks 6

  @doc """
  Parses the BTS file at `path`.

  Only send and delay actions are returned.
  """
  def parse(path) do
    <<
      _magic::binary-size(4),
      _version::little-size(32),
      _future::size(192),
      actions::binary
    >> = File.read!(path)

    reduce_actions(actions)
  end

  defp reduce_actions(bin, actions \\ [])

  defp reduce_actions(<<>>, actions), do: Enum.reverse(actions)

  defp reduce_actions(
         <<
           @action_send_command::little-size(16),
           size::little-size(16),
           data::binary-size(size),
           rest::binary
         >>,
         actions
       ) do
    debug(:send, data)
    reduce_actions(rest, [data | actions])
  end

  defp reduce_actions(
         <<
           @action_wait_event::little-size(16),
           size::little-size(16),
           data::binary-size(size),
           rest::binary
         >>,
         actions
       ) do
    debug(:wait, data)
    reduce_actions(rest, actions)
  end

  defp reduce_actions(
         <<
           @action_serial::little-size(16),
           size::little-size(16),
           data::binary-size(size),
           rest::binary
         >>,
         actions
       ) do
    debug(:serial, data)
    reduce_actions(rest, actions)
  end

  defp reduce_actions(
         <<
           @action_delay::little-size(16),
           size::little-size(16),
           data::binary-size(size),
           rest::binary
         >>,
         actions
       ) do
    debug(:delay, data)
    reduce_actions(rest, [data | actions])
  end

  defp reduce_actions(
         <<
           @action_run_script::little-size(16),
           size::little-size(16),
           data::binary-size(size),
           rest::binary
         >>,
         actions
       ) do
    debug(:run_script, data)
    reduce_actions(rest, actions)
  end

  defp reduce_actions(
         <<
           @action_remarks::little-size(16),
           size::little-size(16),
           data::binary-size(size),
           rest::binary
         >>,
         actions
       ) do
    debug(:remarks, data)
    reduce_actions(rest, actions)
  end

  defp debug(:remarks, bin) do
    :ok = Logger.debug("remarks   " <> String.replace(bin, <<0>>, <<>>))
  end

  defp debug(label, bin) do
    :ok = Logger.debug(String.pad_trailing("#{label}", 10, " ") <> inspect(bin))
  end
end

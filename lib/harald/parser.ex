defmodule Harald.Parser do
  @moduledoc """
  Parses Harald's representations of the Bluetooth spec into runtime functionality.
  """

  alias Harald.{HCI, HCI.Event, Parser.Context, Spec.Parser}
  alias Harald.Parser.{Context, Parameters}

  @doc """
  Returns the parsed Bluetooth spec.
  """
  def parse_spec(spec) do
    Enum.reduce(spec, Context.new(spec), &reduce_spec(&1, &2))
  end

  defp reduce_spec({:error_codes, _partial}, context), do: context

  defp reduce_spec({:packets, _partial}, context), do: context

  defp reduce_spec({:generic_access_profile, spec}, context) do
    Enum.reduce(spec, context, fn
      data_type, context ->
        context
        |> Map.put(
          :target,
          Context.target(:generic_access_profile, data_type.name, [], data_type)
        )
        |> Parameters.parse()
        |> Map.update(:gap_names, [data_type.name], &[data_type.name | &1])
    end)
  end

  defp reduce_spec({:command_groups, command_groups}, context) do
    Enum.reduce(command_groups, context, fn command_group, context ->
      Enum.reduce(command_group.commands, context, fn command, context ->
        <<opcode_int::size(16)>> = <<command_group.id::size(6), command.id::size(10)>>
        opcode = <<opcode_int::little-size(16)>>
        prefix = [1 | :binary.bin_to_list(opcode)]

        context
        |> update_in([:types, :opcode, :values], &[opcode | &1])
        |> put_in([:types, :opcode, :mapping, opcode], command.name)
        |> Map.put(
          :target,
          Context.target(:return, command.name, [], %{parameters: command.return})
        )
        |> Parameters.parse()
        |> Map.put(:target, Context.target(:command, command.name, prefix, command))
        |> Parameters.parse()
      end)
    end)
  end

  defp reduce_spec({:events, spec}, context) do
    Enum.reduce(spec, context, fn
      %{subevents: subevents} = event, context ->
        reduce_spec({:subevents, {event.id, event.name}, subevents}, context)

      event, context ->
        prefix = [4, event.id]

        context
        |> Map.put(:target, Context.target(:event, event.name, prefix, event))
        |> Parameters.parse()
    end)
  end

  defp reduce_spec({:subevents, {event_id, event_name}, spec}, context) do
    prefix = [4, event_id]

    Enum.reduce(spec, context, fn
      subevent, context ->
        context
        |> Map.put(
          :target,
          Context.target(:subevent, {event_name, subevent.name}, prefix, subevent)
        )
        |> Parameters.parse()
    end)
  end

  @doc """
  Maps `transform` over byte length delimited elements of `list` and returns the result.

      iex> split_map(<<1, 97, 2, 97, 98>>)
      ["a", "ab"]
  """
  @spec split_map(binary(), (length :: integer(), data :: binary() -> term()), []) :: []
  def split_map(bin, transform \\ fn _, x -> x end, acc \\ [])

  def split_map(<<>>, _, acc), do: Enum.reverse(acc)

  def split_map(<<length, data::binary-size(length), rest::binary>>, transform, acc) do
    rest
    |> split_map(transform, [transform.(length, data) | acc])
  end

  @doc """
  Maps `transform` over `list` and returns the joined result delimited by byte length.

      iex> join_map(["a", "ab"])
      <<1, 97, 2, 97, 98>>
  """
  @spec join_map(list :: [], transform :: (term() -> binary()), acc :: iodata()) :: binary()
  def join_map(list, transform \\ &to_string(&1), acc \\ "")

  def join_map(list, transform, acc) do
    list
    |> Enum.reduce(acc, fn element, acc ->
      element = transform.(element)
      [[byte_size(element), element] | acc]
    end)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end
end

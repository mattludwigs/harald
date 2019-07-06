defmodule Harald.TransportTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  import Mox, only: [expect: 3, set_mox_global: 1, verify_on_exit!: 1]
  alias Harald.Transport
  alias Harald.Transport.UARTBehaviourMock

  doctest Transport, import: true

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    expect(UARTBehaviourMock, :start_link, fn -> {:ok, nil} end)
    expect(UARTBehaviourMock, :open, fn _, _, _ -> :ok end)
    namespace = namespace()
    start_link_ret = Transport.start_link(default_args(namespace))
    %{namespace: namespace, start_link_ret: start_link_ret}
  end

  test "start_link/1", context do
    assert {:ok, pid} = context.start_link_ret
  end

  # test "option: handle_start" do
  #   parent = self()
  #   ref = make_ref()
  #   expect(UARTBehaviourMock, :start_link, fn -> {:ok, nil} end)
  #   expect(UARTBehaviourMock, :open, fn _, _, _ -> :ok end)

  #   default_args()
  #   |> Map.put(:handle_start, fn ->
  #     send(parent, ref)
  #     {:ok, []}
  #   end)
  #   |> Transport.start_link()

  #   assert_receive ^ref, 500
  # end

  test "send_binary/2", context do
    check all(bin <- binary()) do
      UARTBehaviourMock
      |> expect(:write, fn _, _ -> :ok end)

      assert :ok == Transport.send_binary(context.namespace, bin)
    end
  end

  test "add_handler/2", context do
    assert :ok == Transport.add_handler(context.namespace, self())
    pid = self()
    assert %{handlers: [^pid]} = :sys.get_state(Transport.name(context.namespace))
  end

  defp default_args(namespace) do
    %{
      adapter: %{args: %{module: UARTBehaviourMock}},
      device: "/dev/null",
      namespace: namespace
    }
  end

  defp namespace do
    :printable
    |> StreamData.string()
    |> Enum.at(0)
    |> String.to_atom()
  end
end

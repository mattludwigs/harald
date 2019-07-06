defmodule Harald.Transport.UARTTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  import Mox, only: [expect: 3, set_mox_global: 1, verify_on_exit!: 1]
  alias Harald.Transport.{UART, UARTBehaviourMock}

  doctest UART, import: true

  setup :set_mox_global
  setup :verify_on_exit!

  describe "name/1" do
    property "the produced atom is of the form {prefix}{namespace}" do
      check all(namespace <- gen_namespace()) do
        assert String.to_atom("#{UART}.namespace.#{namespace}") == UART.name(namespace)
      end
    end
  end

  describe "setup/1" do
    property "good arguments result in success" do
      check all(args <- gen_args()) do
        common_expectations()
        {:ok, %{adapter_pid: pid}} = UART.start_link(args)
        UART.stop(args.namespace)
        assert is_pid(pid)
      end
    end

    property "name collisions return an error tuple" do
      check all(args <- gen_args()) do
        common_expectations()
        assert {:ok, _} = UART.start_link(args)
        assert {:error, {:already_started, _}} = UART.start_link(args)
        UART.stop(args.namespace)
      end
    end
  end

  property "Circuits.UART msgs are forwarded to the parent" do
    check all(
            msg <- term(),
            args <- gen_args()
          ) do
      common_expectations()
      assert {:ok, %{adapter_pid: pid}} = UART.start_link(args)
      send(pid, {:circuits_uart, nil, msg})
      assert_receive {:transport_adapter, ^msg}
      UART.stop(args.namespace)
    end
  end

  defp common_expectations do
    UARTBehaviourMock
    |> expect(:start_link, fn -> {:ok, nil} end)
    |> expect(:open, fn _, _, _ -> :ok end)
  end

  def gen_args do
    gen all(
          namespace <- gen_namespace(),
          device <- string(:printable)
        ) do
      %{
        device: device,
        module: UARTBehaviourMock,
        namespace: namespace
      }
    end
  end

  defp gen_namespace do
    :printable
    |> string()
    |> map(&String.to_atom/1)
  end
end

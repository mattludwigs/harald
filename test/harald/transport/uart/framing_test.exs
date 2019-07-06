defmodule Harald.Transport.UART.FramingTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Harald.Transport.UART.Framing
  alias Harald.Transport.UART.Framing.State

  doctest Harald.Transport.UART.Framing, import: true

  describe "init/1" do
    property "returns a fresh state" do
      check all(args <- term()) do
        assert {:ok, %State{}} == Framing.init(args)
      end
    end
  end

  describe "add_framing/2" do
    property "returns data and state unchanged" do
      check all(
              data <- binary(),
              state <- term()
            ) do
        assert {:ok, data, state} == Framing.add_framing(data, state)
      end
    end
  end

  describe "flush/2" do
    property ":transmit returns state unchanged" do
      check all(state <- term()) do
        assert state == Framing.flush(:transmit, state)
      end
    end

    property ":receive returns a fresh state" do
      check all(state <- term()) do
        assert %State{} == Framing.flush(:receive, state)
      end
    end

    property ":both returns a fresh state" do
      check all(state <- term()) do
        assert %State{} == Framing.flush(:both, state)
      end
    end
  end

  describe "frame_timeout/1" do
    property "returns the state and an empty binary" do
      check all(state <- term()) do
        assert {:ok, [state], <<>>} == Framing.frame_timeout(state)
      end
    end
  end

  describe "remove_framing/2" do
    property "bad packet types return the remaining data in error" do
      check all(
              packet_type <- integer(),
              packet_type not in 2..4,
              rest <- bitstring(),
              binary = <<packet_type, rest::bits>>
            ) do
        assert {:ok, [{:error, {:bad_packet_type, binary}}], %State{}} ==
                 Framing.remove_framing(binary, %State{})
      end
    end

    # property "returns when receiving complete event(s)" do
    #   check all(
    #           packets <- list_of(Generators.HCI.generate(:event)),
    #           binary = Enum.join(packets)
    #         ) do
    #     assert {:ok, ^packets, %{frame: "", remaining_bytes: nil}} =
    #              Framing.remove_framing(binary, %State{})
    #   end
    # end

    # property "returns when receiving event(s) that will end in_frame" do
    #   check all(
    #           [head | tail] <- list_of(Generators.HCI.generate(:event), length: 1),
    #           packets = Enum.join(tail),
    #           head_length = byte_size(head),
    #           partial_length <- integer(1..(head_length - 1)),
    #           {0, partial_packet, _} = Framing.binary_split(head, partial_length)
    #         ) do
    #     # the third byte in event packets is the length
    #     remaining_bytes =
    #       if partial_length >= 3 do
    #         head_length - partial_length
    #       else
    #         nil
    #       end

    #     assert {:in_frame, tail,
    #             %State{
    #               frame: partial_packet,
    #               remaining_bytes: remaining_bytes
    #             }} ==
    #              Framing.remove_framing(packets <> partial_packet, %State{})
    #   end
    # end
  end
end

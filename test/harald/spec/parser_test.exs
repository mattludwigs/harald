defmodule Harald.Spec.ParserTest do
  use ExUnit.Case, async: true
  alias Harald.Parser
  alias Harald.Parser.Context

  doctest Harald.HCI, import: true

  describe "command_groups" do
    test "command" do
      spec = [
        error_codes: %{
          0x00 => "Success",
          0x01 => "Unknown HCI Command"
        },
        packets: [],
        command_groups: [
          %{
            id: 3,
            commands: [
              %{
                name: "HCI_Read_Local_Name",
                id: 20,
                parameters: [],
                return: [
                  %{name: "Status", type: :error_code},
                  %{name: "Local_Name", size: 8 * 248, type: :null_terminated}
                ]
              }
            ]
          }
        ],
        events: [
          %{
            name: "HCI_Command_Complete",
            id: 14,
            parameters: [
              %{name: "Num_HCI_Command_Packets"},
              %{name: "Command_Opcode", type: :opcode},
              %{name: "Return_Parameter(s)", type: :command_return}
            ]
          },
          %{
            name: "HCI_LE_Meta",
            id: 62,
            subevents: [
              %{
                name: "HCI_LE_Advertising_Report",
                parameters: [
                  %{name: "Subevent_Code", type: :subevent_code, value: 2},
                  %{name: "Num_Reports", size: 8, type: :integer, values: 1..25},
                  %{
                    name: :reports,
                    parameters: [
                      %{name: "Event_Type", size: 8, values: 0..4},
                      %{name: "Address_Type", size: 8, values: 0..3},
                      %{name: "Address", size: 8 * 6, type: :binary},
                      %{name: "Length_Data"},
                      %{
                        name: "Data",
                        size: "Length_Data",
                        type: {:list, :generic_access_profile}
                      },
                      %{name: "RSS"}
                    ],
                    type: :arrayed_data
                  }
                ]
              }
            ]
          }
        ]
      ]

      # assert general response

      assert %{ast_maps: actual_ast_maps, types: types} = Parser.parse_spec(spec)
      assert 4 = length(actual_ast_maps)

      # assert subevent
      schema =
        Macro.escape([
          {"Event_Type", 8},
          {"Address_Type", 8},
          {"Address", 48},
          {"Length_Data", {:variable, "Data", 8}},
          {"Data", "Length_Data", {:list, :generic_access_profile}},
          {"RSS", 8}
        ])

      assert %{
               deserializers: actual_deserializers,
               serializers: actual_serializers
             } = Enum.at(actual_ast_maps, 0)

      expected_deserializers = [
        [
          quote context: Elixir do
            def deserialize(<<4, 62, _parameter_total_length, 2, v2::size(8), v9::binary>>) do
              {_, v9} =
                Harald.HCI.ArrayedData.deserialize(
                  unquote(schema),
                  v2,
                  v9
                )

              %{
                :type => :event,
                :event_code => "HCI_LE_Meta",
                "Subevent_Code" => "HCI_LE_Advertising_Report",
                "Num_Reports" => v2,
                :reports => v9
              }
            end
          end
        ]
      ]

      assert expected_deserializers == actual_deserializers

      expected_serializers = [
        [
          quote context: Elixir do
            def serialize(%{
                  :event_code => "HCI_LE_Meta",
                  :type => :event,
                  "Subevent_Code" => "HCI_LE_Advertising_Report",
                  "Num_Reports" => v2,
                  :reports => v9
                }) do
              {_, v9} = Harald.HCI.ArrayedData.serialize(unquote(schema), v9)
              parameters = <<2, v2::size(8), v9::binary>>
              parameter_total_length = byte_size(parameters)
              <<4, 62, parameter_total_length, parameters::binary>>
            end
          end
        ]
      ]

      assert expected_serializers == actual_serializers

      # assert event
      assert %{
               deserializers: actual_deserializers,
               serializers: actual_serializers
             } = Enum.at(actual_ast_maps, 1)

      expected_deserializers = [
        [
          quote context: Elixir do
            def deserialize(
                  <<4, 14, _parameter_total_length, v1::size(8), v2::binary-size(2), v3::binary>>
                ) do
              v2 = Harald.HCI.command_name(v2)
              v3 = Harald.HCI.deserialize({{:return, v2}, v3})

              %{
                :type => :event,
                :event_code => "HCI_Command_Complete",
                "Num_HCI_Command_Packets" => v1,
                "Command_Opcode" => v2,
                "Return_Parameter(s)" => v3
              }
            end
          end
        ]
      ]

      assert expected_deserializers == actual_deserializers

      opcodes = types.opcode.values

      expected_serializers = [
        [
          quote context: Elixir do
            def serialize(%{
                  :event_code => "HCI_Command_Complete",
                  :type => :event,
                  "Num_HCI_Command_Packets" => v1,
                  "Command_Opcode" => v2,
                  "Return_Parameter(s)" => v3
                }) do
              v2 = Harald.HCI.command_opcode(v2)
              v3 = Harald.HCI.serialize(v3)
              parameters = <<v1::size(8), v2::binary-size(2), v3::binary>>
              parameter_total_length = byte_size(parameters)
              <<4, 14, parameter_total_length, parameters::binary>>
            end
          end
        ]
      ]

      assert expected_serializers == actual_serializers

      # assert command

      assert %{
               deserializers: actual_deserializers,
               serializers: actual_serializers
             } = Enum.at(actual_ast_maps, 2)

      expected_deserializers = [
        quote context: Elixir do
          def deserialize(<<1, 20, 12, 0>>) do
            %{type: :command, opcode: "HCI_Read_Local_Name"}
          end
        end
      ]

      assert expected_deserializers == actual_deserializers

      expected_serializers = [
        quote context: Elixir do
          def serialize(%{opcode: "HCI_Read_Local_Name", type: :command}) do
            <<1, 20, 12, 0>>
          end
        end
      ]

      assert expected_serializers == actual_serializers

      # assert command return

      assert %{
               deserializers: actual_deserializers,
               serializers: actual_serializers
             } = Enum.at(actual_ast_maps, 3)

      expected_deserializers = [
        [
          quote context: Elixir do
            def deserialize({{:return, "HCI_Read_Local_Name"}, <<v1, v2::binary-size(248)>>}) do
              v1 = Harald.HCI.error_desc(v1)
              [head | tail] = String.split(v2, <<0>>)
              v2 = {head, Enum.join(tail)}

              %{
                :type => :return,
                :opcode => "HCI_Read_Local_Name",
                "Status" => v1,
                "Local_Name" => v2
              }
            end
          end
        ]
      ]

      assert expected_deserializers == actual_deserializers

      expected_serializers = [
        [
          quote context: Elixir do
            def serialize(%{
                  :opcode => "HCI_Read_Local_Name",
                  :type => :return,
                  "Status" => v1,
                  "Local_Name" => v2
                }) do
              v1 = Harald.HCI.error_code(v1)
              v2 = elem(v2, 0) <> <<0>> <> elem(v2, 1)
              <<v1, v2::binary-size(248)>>
            end
          end
        ]
      ]

      assert expected_serializers == actual_serializers
    end
  end
end

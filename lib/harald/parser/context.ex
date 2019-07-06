defmodule Harald.Parser.Context do
  @doc false

  alias Harald.Parser.Ast
  alias Harald.Parser.Parameters.{Deserializers, Serializers}

  @behaviour Access

  @type target ::
          %{
            parametere_index: 1,
            parameter_var: Ast.var(:v1),
            partial: nil,
            serializers: [],
            deserializers: []
          }
          | nil

  # todo update spec
  @type t :: %{
          ast_maps: [],
          spec: [],
          target: nil,
          types: %{
            ad_structures: %{},
            arrayed_data: %{},
            binary: %{},
            boolean: %{values: 0..1},
            command_return: %{values: %{}},
            error_code: %{values: []},
            flag: %{size: 2},
            generic_access_profile: %{},
            handle: %{size: 12, values: 0..3839},
            integer: %{},
            list: %{},
            null_terminated: %{},
            opcode: %{
              size: 16,
              mapping: %{},
              parameters: [%{name: String.t(), size: integer()}],
              values: []
            },
            subevent_code: %{mapping: %{}}
          }
        }

  defstruct ast_maps: [],
            spec: [],
            target: nil,
            types: %{
              ad_structures: %{},
              arrayed_data: %{},
              binary: %{},
              boolean: %{values: 0..1},
              command_return: %{values: %{}},
              error_code: %{values: []},
              flag: %{size: 2},
              generic_access_profile: %{},
              handle: %{size: 12, values: 0..3839},
              integer: %{},
              list: %{},
              null_terminated: %{},
              opcode: %{
                size: 16,
                mapping: %{},
                parameters: [%{name: "OGF", size: 6}, %{name: "OCF", size: 10}],
                values: []
              },
              subevent_code: %{mapping: %{}}
            }

  def new(spec) do
    error_code_ids = Map.keys(Keyword.fetch!(spec, :error_codes))

    %{
      ast_maps: [],
      spec: spec,
      target: nil,
      types: %{
        ad_structures: %{},
        arrayed_data: %{},
        binary: %{},
        boolean: %{values: 0..1},
        command_return: %{values: %{}},
        error_code: %{values: error_code_ids},
        flag: %{size: 2},
        generic_access_profile: %{},
        handle: %{size: 12, values: 0..3839},
        integer: %{},
        list: %{},
        null_terminated: %{},
        opcode: %{
          size: 16,
          mapping: %{},
          parameters: [%{name: "OGF", size: 6}, %{name: "OCF", size: 10}],
          values: []
        },
        subevent_code: %{mapping: %{}}
      }
    }
  end

  def target(spec_type, name, prefix, partial) do
    %{
      deserializers: Deserializers.ast(spec_type, name, prefix),
      parameter: parameter(),
      partial: partial,
      processed_parameters: [],
      serializers: Serializers.ast(spec_type, name, prefix),
      spec_type: spec_type
    }
  end

  def parameter, do: %{index: 1, var: Ast.var(:v1)}

  defimpl Enumerable do
    def reduce(data, acc, fun) do
      data
      |> Map.from_struct()
      |> Enum.reduce(acc, fun)
    end

    def slice(data) do
      data
      |> Map.from_struct()
      |> Enum.slice()
    end

    def member?(data, element) do
      data
      |> Map.from_struct()
      |> Enum.member?(element)
    end

    def count(data) do
      data
      |> Map.from_struct()
      |> Enum.count()
    end
  end

  @impl Access
  defdelegate fetch(context, key), to: Map

  @impl Access
  defdelegate get_and_update(context, key, fun), to: Map

  @impl Access
  defdelegate pop(context, key), to: Map
end

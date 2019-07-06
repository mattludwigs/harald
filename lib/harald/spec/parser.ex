if false do
  defmodule Harald.Spec.Parser do
    @moduledoc false

    alias Harald.Parser.Ast
    require Logger

    def parse({_section, _spec}, state), do: state

    defp generate_helpers(state) do
      command_name_funs =
        Enum.reduce(state.types.opcode.mapping, [], fn {opcode, command_name}, acc ->
          <<int_opcode::size(16)>> = opcode

          ast =
            quote do
              def command_name(unquote(opcode)), do: unquote(command_name)
              def command_name(unquote(int_opcode)), do: unquote(command_name)
              def command_opcode(unquote(command_name)), do: unquote(opcode)
            end

          [ast | acc]
        end)

      error_funs =
        Enum.reduce(Keyword.fetch!(state.spec, :error_codes), [], fn {error_code, error_desc},
                                                                     acc ->
          ast =
            quote do
              def error_code(unquote(error_desc)), do: unquote(error_code)
              def error_desc(unquote(error_code)), do: unquote(error_desc)
            end

          [ast | acc]
        end)

      helpers = command_name_funs ++ error_funs
      Map.put(state, :helpers, helpers)
    end

    # defp process_parameters(state, spec_type, params) do
    #   state =
    #     params
    #     |> Enum.reduce(state, fn
    #       param, state ->
    #         {expanded_param, state} = expand_parameter(param, params, state)

    #         state
    #         |> process_generators(spec_type, expanded_param)
    #         |> process_izers(:deserializers, spec_type, expanded_param)
    #         |> process_izers(:serializers, spec_type, expanded_param)
    #         |> increment_param_index(expanded_param)
    #     end)
    #     |> parameters_finish()

    #   state
    #   |> Map.put(:ast_map, nil)
    #   |> Map.update!(:ast_maps, &[state.ast_map | &1])
    # end

    # defp process_generators(state, spec_type, param)

    # defp process_generators(state, spec_type, param) when spec_type in [:event, :subevent] do
    #   generator = generator_chunk(param, state)

    #   state
    #   |> update_in([:ast_map, :generators], fn generators ->
    #     Enum.map(generators, fn
    #       {:def, m1, [head, [do: {:gen, [], [{:all, [], acc_clauses}, body]}]]} ->
    #         {clauses_head,
    #          [
    #            {:=, [], [parameters, {:<<>>, [], acc_bin_args}]},
    #            parameter_total_length
    #          ]} = Enum.split(acc_clauses, -2)

    #         clauses_head = clauses_head ++ generator.gen_clauses
    #         bin_args = acc_bin_args ++ generator.gen_body

    #         clauses =
    #           clauses_head ++
    #             [{:=, [], [parameters, {:<<>>, [], bin_args}]}, parameter_total_length]

    #         {:def, m1, [head, [do: {:gen, [], [{:all, [], clauses}, body]}]]}
    #     end)
    #   end)
    # end

    # defp process_generators(state, _spec_type, param) do
    #   generator = generator_chunk(param, state)

    #   state
    #   |> update_in([:ast_map, :generators], fn generators ->
    #     Enum.map(generators, fn ast ->
    #       Macro.prewalk(ast, fn
    #         {:gen, [], [{:all, [], clauses}, [do: {:<<>>, [], args}]]} ->
    #           clauses = clauses ++ generator.gen_clauses
    #           args = args ++ generator.gen_body
    #           {:gen, [], [{:all, [], clauses}, [do: {:<<>>, [], args}]]}

    #         ast ->
    #           ast
    #       end)
    #     end)
    #   end)
    # end

    # defp generator_chunk(param, state) do
    #   %{gen_body: gen_body(param, state), gen_clauses: gen_clauses(param, state)}
    # end

    defp ast_map(type, name, prefix)

    defp ast_map(:empty, _, _) do
      %{
        arrayed_data: false,
        deserializers: [],
        generators: [],
        serializers: [],
        processed_parameters: []
      }
    end

    defp ast_map(type, name, prefix) do
      %{
        arrayed_data: false,
        deserializers: ast_map_deserializers(type, name, prefix),
        generators: ast_map_generators(type, name, prefix),
        subevent_name: ast_subevent_name(type, name),
        parameter_var: Ast.var(:v1),
        parameter_index: 1,
        processed_parameters: [],
        serializers: ast_map_serializers(type, name, prefix)
      }
    end

    defp ast_subevent_name(:subevent, {_, subevent_name}), do: subevent_name

    defp ast_subevent_name(_, _), do: nil

    defp ast_map_generators(:command, name, prefix) do
      [
        quote do
          def generate(unquote(name)) do
            gen all(bin <- StreamData.constant(unquote({:<<>>, [], prefix ++ [0]}))) do
              <<bin::binary>>
            end
          end
        end
      ]
    end

    defp ast_map_generators(:event, name, prefix) do
      [
        quote do
          def generate(unquote(name)) do
            gen all(
                  bin <- StreamData.constant(unquote({:<<>>, [], prefix})),
                  parameters = <<>>,
                  parameter_total_length = byte_size(parameters)
                ) do
              <<bin::binary, parameter_total_length, parameters::binary>>
            end
          end
        end
      ]
    end

    defp ast_map_generators(:subevent, name, prefix) do
      [
        quote do
          def generate(unquote(name)) do
            gen all(
                  bin <- StreamData.constant(unquote({:<<>>, [], prefix})),
                  parameters = <<>>,
                  parameter_total_length = byte_size(parameters)
                ) do
              <<bin::binary, parameter_total_length, parameters::binary>>
            end
          end
        end
      ]
    end

    defp ast_map_generators(type, name, prefix) when type in [:return, :generic_access_profile] do
      [
        quote do
          def generate({unquote(type), unquote(name)}) do
            gen all(bin <- StreamData.constant(unquote({:<<>>, [], prefix}))) do
              <<bin::binary>>
            end
          end
        end
      ]
    end

    defp spec_unit(name, parameters), do: %{name: name, parameters: parameters}
  end
end

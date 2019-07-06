defmodule Harald.Parser.Ast do
  def var(atom), do: Macro.var(atom, Elixir)

  def concat_do_value({:__block__, _, acc_block_args}, new_transforms, new_ret_args) do
    {{a, b, acc_ret_args}, acc_transforms} = List.pop_at(acc_block_args, -1)
    {:__block__, [], acc_transforms ++ new_transforms ++ [{a, b, acc_ret_args ++ new_ret_args}]}
  end

  def concat_do_value({a, b, acc_ret_args}, [], new_ret_args) do
    {a, b, acc_ret_args ++ new_ret_args}
  end

  def concat_do_value({a, b, acc_ret_args}, new_transforms, new_ret_args) do
    {:__block__, [], new_transforms ++ [{a, b, acc_ret_args ++ new_ret_args}]}
  end
end

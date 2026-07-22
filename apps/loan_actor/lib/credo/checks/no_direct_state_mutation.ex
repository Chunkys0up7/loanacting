defmodule LoanActor.Credo.NoDirectStateMutation do
  @moduledoc """
  Enforces the data-model rule that `LoanActor.State.transition/2` is the
  only legal mutation entrypoint for `%LoanActor.State{}` (FT-012): flags
  struct-update syntax (`%LoanActor.State{expr | ...}`, or its locally
  aliased form after `alias LoanActor.State[, as: X]`) appearing anywhere
  outside `LoanActor.State.transition/2` itself.

  Scope note (documented limitation, not an oversight): this check resolves
  the struct name via full qualification (`LoanActor.State`) or a
  single-level `alias`. It does not resolve `alias LoanActor.{State, ...}`
  multi-alias groups (unused in this codebase) or bare-map updates that
  never name the struct (`%{var | field: val}`) — those are indistinguishable
  from an ordinary map update by static syntax alone, which is why
  `LoanActor.State.transition/2` itself is written with the bare form.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Mutating %LoanActor.State{} anywhere except State.transition/2 bypasses
      the state machine, the diary append, and the version increment. All
      mutations must flow through transition/2 (constitution Principle IV;
      clarifications.md Q4).
      """
    ]

  alias Credo.SourceFile

  @target_module [:LoanActor, :State]
  @allowed_function :transition

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    ctx = %{module: [], aliases: %{}, in_scope: false}
    {issues, _ctx} = walk(ast, ctx, issue_meta)
    issues
  end

  # ---- scope tracking ----

  defp walk({:defmodule, _, [{:__aliases__, _, mod_parts}, [do: body]]}, ctx, issue_meta) do
    {issues, _} = walk(body, %{ctx | module: mod_parts, aliases: %{}}, issue_meta)
    {issues, ctx}
  end

  defp walk({:alias, _, [{:__aliases__, _, mod_parts}]}, ctx, _issue_meta) do
    as_name = List.last(mod_parts)
    {[], %{ctx | aliases: Map.put(ctx.aliases, as_name, mod_parts)}}
  end

  defp walk(
         {:alias, _, [{:__aliases__, _, mod_parts}, [as: {:__aliases__, _, [as_name]}]]},
         ctx,
         _issue_meta
       ) do
    {[], %{ctx | aliases: Map.put(ctx.aliases, as_name, mod_parts)}}
  end

  defp walk({def_kw, _, [head, [do: body]]}, ctx, issue_meta) when def_kw in [:def, :defp] do
    allowed? = ctx.module == @target_module and function_name(head) == @allowed_function
    {issues, _} = walk(body, %{ctx | in_scope: ctx.in_scope or allowed?}, issue_meta)
    {issues, ctx}
  end

  # ---- the pattern being checked for: named struct-update syntax ----

  defp walk(
         {:%, meta, [{:__aliases__, _, name_parts}, {:%{}, _, [{:|, _, _}]}]},
         ctx,
         issue_meta
       ) do
    if resolve(name_parts, ctx.aliases) == @target_module and not ctx.in_scope do
      {[issue_for(issue_meta, meta[:line])], ctx}
    else
      {[], ctx}
    end
  end

  # ---- multi-statement bodies: alias/scope registrations from an earlier
  # statement must be visible to later statements in the SAME block ----

  defp walk({:__block__, _, stmts}, ctx, issue_meta) do
    {issues_lists, _final_ctx} =
      Enum.map_reduce(stmts, ctx, fn stmt, acc_ctx ->
        walk(stmt, acc_ctx, issue_meta)
      end)

    {List.flatten(issues_lists), ctx}
  end

  # ---- generic recursion (context does not leak to siblings) ----

  defp walk({form, _meta, args}, ctx, issue_meta) when is_list(args) do
    # `form` matters for remote calls / dot-access: `Module.fn(x)` and
    # `expr.field` are both AST `{{:., _, [target, name]}, _, args}` — a
    # struct-update expression used as the call target or dot-access
    # receiver lives INSIDE `form`, not `args`, and would otherwise never
    # be visited (an atom `form`, e.g. `:def`, is harmless — it just falls
    # through to the leaf catch-all below).
    {form_issues, _} = walk(form, ctx, issue_meta)
    {form_issues ++ collect(args, ctx, issue_meta), ctx}
  end

  defp walk(list, ctx, issue_meta) when is_list(list) do
    {collect(list, ctx, issue_meta), ctx}
  end

  defp walk({a, b}, ctx, issue_meta) do
    {issues_a, _} = walk(a, ctx, issue_meta)
    {issues_b, _} = walk(b, ctx, issue_meta)
    {issues_a ++ issues_b, ctx}
  end

  defp walk(_leaf, ctx, _issue_meta), do: {[], ctx}

  defp collect(nodes, ctx, issue_meta) do
    Enum.flat_map(nodes, fn node ->
      {issues, _} = walk(node, ctx, issue_meta)
      issues
    end)
  end

  defp function_name({:when, _, [inner | _]}), do: function_name(inner)
  defp function_name({name, _, _args}) when is_atom(name), do: name
  defp function_name(_), do: nil

  defp resolve([single], aliases) when is_map_key(aliases, single) do
    Map.fetch!(aliases, single)
  end

  defp resolve(parts, _aliases), do: parts

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message:
        "Direct mutation of %LoanActor.State{} is forbidden outside LoanActor.State.transition/2.",
      trigger: "%LoanActor.State{",
      line_no: line_no
    )
  end
end

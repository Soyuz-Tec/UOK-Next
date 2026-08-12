defmodule UokNext.Modules.Platform.Agents.Domain.AgentPlan do
  @moduledoc """
  Pure validation and graph rules for governed, non-executing agent plans.
  """

  @identifier_pattern ~r/^[a-z][a-z0-9_.:-]{2,119}$/
  @subject_pattern ~r/^[a-z][a-z0-9_.:-]{1,119}$/
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @actions ~w(read prepare reconcile recommend propose_command)
  @decisions ~w(approve hold)
  @forbidden_keys ~w(arguments command endpoint execute model prompt tool tool_name url)
  @forbidden_atom_keys ~w(arguments command endpoint execute model prompt tool tool_name url)a

  @spec validate_proposal(map()) :: {:ok, map()} | {:error, map()}
  def validate_proposal(attrs) when is_map(attrs) do
    with :ok <- no_execution_fields(attrs),
         {:ok, runbook_key} <- identifier(value(attrs, :runbook_key), :runbook_key),
         {:ok, runbook_version} <- positive(value(attrs, :runbook_version), :runbook_version),
         {:ok, subject_type} <- subject_type(value(attrs, :subject_type)),
         {:ok, subject_id} <- uuid(value(attrs, :subject_id), :subject_id),
         {:ok, subject_version} <- positive(value(attrs, :subject_version), :subject_version),
         {:ok, steps} <- steps(value(attrs, :steps)),
         :ok <- dependency_graph(steps),
         {:ok, evidence_ids} <- evidence_ids(value(attrs, :evidence_ids) || []),
         {:ok, reason} <- reason(value(attrs, :reason)) do
      proposal = %{
        runbook_key: runbook_key,
        runbook_version: runbook_version,
        subject_type: subject_type,
        subject_id: subject_id,
        subject_version: subject_version,
        step_graph: %{"items" => Enum.map(steps, &json_step/1)},
        evidence_ids: evidence_ids,
        reason: reason
      }

      {:ok, Map.put(proposal, :plan_sha256, plan_sha256(proposal))}
    end
  end

  def validate_proposal(_attrs), do: error(:command, "must be an object")

  @spec validate_decision_input(map()) :: {:ok, map()} | {:error, map()}
  def validate_decision_input(attrs) when is_map(attrs) do
    with :ok <- no_execution_fields(attrs),
         {:ok, task_id} <- uuid(value(attrs, :task_id), :task_id),
         {:ok, decision} <- member(value(attrs, :decision), :decision, @decisions),
         {:ok, reason} <- reason(value(attrs, :reason)) do
      {:ok, %{task_id: task_id, decision: decision, reason: reason}}
    end
  end

  def validate_decision_input(_attrs), do: error(:command, "must be an object")

  @spec validate_decision(map(), map()) :: {:ok, map()} | {:error, map()}
  def validate_decision(plan, command) when is_map(plan) and is_map(command) do
    with :ok <- proposed(plan), do: {:ok, command}
  end

  def validate_decision(_plan, _command), do: error(:command, "must be an object")

  @spec validate_id(term()) :: {:ok, String.t()} | {:error, map()}
  def validate_id(value), do: uuid(value, :plan_id)

  defp steps(items) when is_list(items) and length(items) in 1..32 do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, validated} ->
      case step(item) do
        {:ok, result} -> {:cont, {:ok, [result | validated]}}
        {:error, details} -> {:halt, {:error, details}}
      end
    end)
    |> reverse_steps()
  end

  defp steps(_items), do: error(:steps, "must contain 1 to 32 plan steps")
  defp reverse_steps({:ok, items}), do: {:ok, Enum.reverse(items)}
  defp reverse_steps(error), do: error

  defp step(item) when is_map(item) do
    with :ok <- no_execution_fields(item),
         {:ok, id} <- identifier(value(item, :id), :step_id),
         {:ok, action} <- member(value(item, :action), :action, @actions),
         {:ok, title} <- text(value(item, :title), :title, 3, 160),
         {:ok, depends_on} <- dependencies(value(item, :depends_on) || []) do
      {:ok, %{id: id, action: action, title: title, depends_on: Enum.sort(depends_on)}}
    end
  end

  defp step(_item), do: error(:step, "must be an object")

  defp dependencies(items) when is_list(items) and length(items) <= 16 do
    with {:ok, validated} <- map_identifiers(items, :depends_on),
         true <- length(validated) == MapSet.size(MapSet.new(validated)) do
      {:ok, validated}
    else
      false -> error(:depends_on, "must contain unique step identifiers")
      {:error, details} -> {:error, details}
    end
  end

  defp dependencies(_items), do: error(:depends_on, "must contain at most 16 step identifiers")

  defp evidence_ids(items) when is_list(items) and length(items) <= 16 do
    with {:ok, validated} <- map_uuids(items, :evidence_ids),
         true <- length(validated) == MapSet.size(MapSet.new(validated)) do
      {:ok, Enum.sort(validated)}
    else
      false -> error(:evidence_ids, "must contain unique UUIDs")
      {:error, details} -> {:error, details}
    end
  end

  defp evidence_ids(_items), do: error(:evidence_ids, "must contain at most 16 UUIDs")

  defp map_identifiers(items, field) do
    map_values(items, &identifier(&1, field))
  end

  defp map_uuids(items, field), do: map_values(items, &uuid(&1, field))

  defp map_values(items, validator) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, validated} ->
      case validator.(item) do
        {:ok, result} -> {:cont, {:ok, [result | validated]}}
        {:error, details} -> {:halt, {:error, details}}
      end
    end)
    |> then(fn
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end)
  end

  defp dependency_graph(steps) do
    ids = Enum.map(steps, & &1.id)

    with true <- length(ids) == MapSet.size(MapSet.new(ids)),
         :ok <- known_dependencies(steps, MapSet.new(ids)),
         :ok <- acyclic(steps) do
      :ok
    else
      false -> error(:steps, "must contain unique step identifiers")
      {:error, details} -> {:error, details}
    end
  end

  defp known_dependencies(steps, ids) do
    if Enum.all?(steps, fn step ->
         Enum.all?(step.depends_on, &(&1 != step.id and MapSet.member?(ids, &1)))
       end),
       do: :ok,
       else: error(:depends_on, "must reference another step in the plan")
  end

  defp acyclic(steps) do
    graph = Map.new(steps, &{&1.id, &1.depends_on})

    Enum.reduce_while(Map.keys(graph), {:ok, MapSet.new()}, fn id, {:ok, visited} ->
      case visit(id, graph, MapSet.new(), visited) do
        {:ok, next_visited} -> {:cont, {:ok, next_visited}}
        :cycle -> {:halt, :cycle}
      end
    end)
    |> case do
      {:ok, _visited} -> :ok
      :cycle -> error(:steps, "must form an acyclic dependency graph")
    end
  end

  defp visit(id, graph, visiting, visited) do
    cond do
      MapSet.member?(visited, id) -> {:ok, visited}
      MapSet.member?(visiting, id) -> :cycle
      true -> visit_dependencies(id, graph, MapSet.put(visiting, id), visited)
    end
  end

  defp visit_dependencies(id, graph, visiting, visited) do
    Enum.reduce_while(Map.fetch!(graph, id), {:ok, visited}, fn dependency, {:ok, seen} ->
      case visit(dependency, graph, visiting, seen) do
        {:ok, next_seen} -> {:cont, {:ok, next_seen}}
        :cycle -> {:halt, :cycle}
      end
    end)
    |> case do
      {:ok, seen} -> {:ok, MapSet.put(seen, id)}
      :cycle -> :cycle
    end
  end

  defp json_step(step) do
    %{
      "id" => step.id,
      "action" => step.action,
      "title" => step.title,
      "depends_on" => step.depends_on
    }
  end

  defp plan_sha256(proposal) do
    proposal
    |> Map.take([
      :runbook_key,
      :runbook_version,
      :subject_type,
      :subject_id,
      :subject_version,
      :step_graph,
      :evidence_ids
    ])
    |> canonicalize()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonicalize(item) when is_map(item) do
    item
    |> Enum.map(fn {key, value} -> {to_string(key), canonicalize(value)} end)
    |> Enum.sort()
  end

  defp canonicalize(item) when is_list(item), do: Enum.map(item, &canonicalize/1)
  defp canonicalize(item) when is_atom(item), do: Atom.to_string(item)
  defp canonicalize(item), do: item

  defp proposed(%{status: "proposed"}), do: :ok
  defp proposed(_plan), do: error(:status, "does not permit a decision")

  defp no_execution_fields(attrs) do
    forbidden? =
      Enum.any?(@forbidden_keys, &Map.has_key?(attrs, &1)) or
        Enum.any?(@forbidden_atom_keys, &Map.has_key?(attrs, &1))

    if forbidden?,
      do:
        error(:execution, "model, tool, endpoint, and command execution fields are not accepted"),
      else: :ok
  end

  defp identifier(item, field) when is_binary(item) do
    normalized = String.trim(item)
    if Regex.match?(@identifier_pattern, normalized), do: {:ok, normalized}, else: invalid(field)
  end

  defp identifier(_item, field), do: invalid(field)

  defp subject_type(item) when is_binary(item) do
    normalized = String.trim(item)

    if Regex.match?(@subject_pattern, normalized),
      do: {:ok, normalized},
      else: invalid(:subject_type)
  end

  defp subject_type(_item), do: invalid(:subject_type)

  defp uuid(item, field) when is_binary(item) do
    normalized = item |> String.trim() |> String.downcase()
    if Regex.match?(@uuid_pattern, normalized), do: {:ok, normalized}, else: invalid_uuid(field)
  end

  defp uuid(_item, field), do: invalid_uuid(field)
  defp positive(item, _field) when is_integer(item) and item > 0, do: {:ok, item}
  defp positive(_item, field), do: error(field, "must be a positive integer")

  defp text(item, field, minimum, maximum) when is_binary(item) do
    normalized = String.trim(item)

    if String.printable?(normalized) and String.length(normalized) in minimum..maximum,
      do: {:ok, normalized},
      else: error(field, "must contain #{minimum} to #{maximum} printable characters")
  end

  defp text(_item, field, minimum, maximum),
    do: error(field, "must contain #{minimum} to #{maximum} printable characters")

  defp reason(item), do: text(item, :reason, 3, 500)

  defp member(item, field, allowed),
    do: if(item in allowed, do: {:ok, item}, else: error(field, "is not allowed"))

  defp invalid(field), do: error(field, "must contain a governed identifier")
  defp invalid_uuid(field), do: error(field, "must be a UUID")
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field: Atom.to_string(field), message: message}}
end

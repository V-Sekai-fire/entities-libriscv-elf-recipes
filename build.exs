# Builds the example ELFs of entities-libriscv in a container.
#
#   elixir build.exs [--recipe fib|program] [--src DIR] [--out DIR] [--jobs N] [--check]
#
# --recipe   build one recipe (default: all of them)
# --src      directory the build runs in inside the container (default /src)
# --out      host directory for the ELFs (default out); each recipe writes
#            OUT/<recipe>/<output>
# --jobs     make -j for the compiler build (default 4)
# --check    exit 1 when an ELF differs from the :sha256 in pins.exs
#
# CONTAINER selects the runtime (default podman; docker also works).

defmodule Recipes do
  @switches [recipe: :string, src: :string, out: :string, jobs: :integer, check: :boolean]

  def main(argv) do
    with {:ok, opts} <- parse(argv),
         {:ok, pins} <- read_pins(),
         {:ok, names} <- select(pins, opts[:recipe]) do
      results = Enum.map(names, &build(&1, pins, opts))
      Enum.each(results, &report/1)

      case Enum.filter(results, &failed?(&1, opts[:check])) do
        [] -> :ok
        bad -> {:error, {:failed, Enum.map(bad, &elem(&1, 0))}}
      end
    end
  end

  defp parse(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, [], []} -> {:ok, Keyword.merge([src: "/src", out: "out", jobs: 4, check: false], opts)}
      {_, rest, invalid} -> {:error, {:bad_arguments, rest ++ Enum.map(invalid, &elem(&1, 0))}}
    end
  end

  defp read_pins do
    path = Path.join(__DIR__, "pins.exs")

    case File.read(path) do
      {:ok, text} -> {:ok, text |> Code.eval_string([], file: path) |> elem(0)}
      {:error, reason} -> {:error, {:pins, reason}}
    end
  end

  defp select(pins, nil), do: {:ok, pins.recipes |> Map.keys() |> Enum.sort()}

  defp select(pins, name) do
    atom = String.to_atom(name)
    if Map.has_key?(pins.recipes, atom), do: {:ok, [atom]}, else: {:error, {:unknown_recipe, name}}
  end

  defp build(name, pins, opts) do
    recipe = pins.recipes[name]
    dest = Path.join(opts[:out], Atom.to_string(name))
    File.rm_rf!(dest)

    args =
      recipe
      |> Map.drop([:sha256, :output])
      |> Map.merge(%{RECIPE: name, LIBRISCV_SHA: pins.libriscv, SRC: opts[:src], JOBS: opts[:jobs]})
      |> Enum.sort()
      |> Enum.flat_map(fn {k, v} -> ["--build-arg", "#{k}=#{v}"] end)

    runtime = System.get_env("CONTAINER", "podman")

    tag = "elf-recipes:#{name}" <> String.replace(opts[:src], ~r/[^A-Za-z0-9]+/, "-")

    cmd =
      ["build", "-f", Path.join(__DIR__, "Containerfile"), "--target", "elf", "-t", tag] ++
        args ++ [__DIR__]

    IO.puts("== #{name}: #{runtime} #{Enum.join(cmd, " ")}")

    with :ok <- run(runtime, cmd, :build),
         :ok <- copy_out(runtime, tag, dest) do
      digest(name, recipe, Path.join(dest, recipe.output))
    else
      {:error, reason} -> {name, {:error, reason}, recipe.sha256}
    end
  end

  # `build --output` does not work with a remote podman (macOS), so copy the
  # ELFs out of a stopped container instead.
  defp copy_out(runtime, tag, dest) do
    container = "elf-recipes-#{System.unique_integer([:positive])}"
    File.mkdir_p!(dest)

    result =
      with :ok <- run(runtime, ["create", "--name", container, tag, "true"], :create) do
        run(runtime, ["cp", "#{container}:/out/.", dest], :copy)
      end

    System.cmd(runtime, ["rm", "-f", container], stderr_to_stdout: true)
    result
  end

  defp run(runtime, args, step) do
    case System.cmd(runtime, args, into: IO.stream(), stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, code} -> {:error, {step, code}}
    end
  end

  defp digest(name, recipe, path) do
    case File.read(path) do
      {:ok, bytes} ->
        sha = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
        {name, {:ok, path, byte_size(bytes), sha}, recipe.sha256}

      {:error, reason} ->
        {name, {:error, {:missing_output, path, reason}}, recipe.sha256}
    end
  end

  defp report({name, {:ok, path, size, sha}, want}) do
    verdict =
      cond do
        want == nil -> "no pinned sha256"
        want == sha -> "matches pins.exs"
        true -> "DIFFERS from pins.exs #{want}"
      end

    IO.puts("#{name}: #{path} #{size} bytes sha256 #{sha} (#{verdict})")
  end

  defp report({name, {:error, reason}, _}), do: IO.puts("#{name}: FAILED #{inspect(reason)}")

  defp failed?({_, {:error, _}, _}, _check), do: true
  defp failed?({_, {:ok, _, _, sha}, want}, true), do: want != sha
  defp failed?(_, false), do: false
end

case Recipes.main(System.argv()) do
  :ok ->
    :ok

  {:error, reason} ->
    IO.puts(:stderr, "error: #{inspect(reason)}")
    System.halt(1)
end

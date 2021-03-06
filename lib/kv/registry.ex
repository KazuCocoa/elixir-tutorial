defmodule KV.Registry do
  use GenServer
 
  ## Client API

  @doc """
  Starts the registry.
  """
  def start_link(table, event_manager, buckets, opts \\ []) do
    # __MODULE__ means current module
    GenServer.start_link(__MODULE__, {table, event_manager, buckets}, opts)
  end

  @doc """
  Looks up the bucket pid for `name` stored in `table`.

  Returns `{:ok, pid}` if a bucket exists, `:error` otherwise.
  """
  def lookup(table, name) do
    case :ets.lookup(table, name) do
      [{^name, bucket}] -> {:ok, bucket}
      [] -> :error
    end
  end

  @doc """
  Ensures there is a bucket associated to the given `name` in `server`.
  """
  def create(server, name) do
    GenServer.call(server, {:create, name})
  end

  ## Server Callbacks

  def init({table, events, buckets}) do
    refs = :ets.foldl(fn {name, pid}, acc ->
      HashDict.put(acc, Process.monitor(pid), name)
    end, HashDict.new, table)
    # init(args) - invoked when the server is started.
    # It must return:
    # 1. {:ok, state}
    # 2. {:ok, state, timeout}
    # 3. :ignore
    # 4. {:stop, reason}
    {:ok, %{names: table, refs: refs, events: events, buckets: buckets}}
  end

  # def handle_call(:stop, _from, state) do
  #   {:stop, :normal, :ok, state}
  # end

  def handle_call({:create, name}, _from, state) do
    case lookup(state.names, name) do
      {:ok, pid} ->
        {:reply, pid, state} # Reply with pid
      :error ->
        {:ok, pid} = KV.Bucket.Supervisor.start_bucket(state.buckets)
        ref = Process.monitor(pid)
        refs = HashDict.put(state.refs, ref, name)
        :ets.insert(state.names, {name, pid})
        GenEvent.sync_notify(state.events, {:create, name, pid})
        {:reply, pid, %{state | refs: refs}} # Reply with pid
    end
  end


  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    {name, refs} = HashDict.pop(state.refs, ref)
    :ets.delete(state.names, name)
    GenEvent.sync_notify(state.events, {:exit, name, pid})
    {:noreply, %{state | refs: refs}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end

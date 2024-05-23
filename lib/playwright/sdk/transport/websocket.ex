defmodule Playwright.SDK.Transport.WebSocket do
  @moduledoc false
  # A transport for negotiating messages with a running Playwright websocket
  # server.

  defstruct([
    :process,
    :monitor
  ])

  # module API
  # ----------------------------------------------------------------------------

  def setup(%{ws_endpoint: ws_endpoint}) do
    uri = URI.parse(ws_endpoint)

    with {:ok, process} <- :gun.open(to_charlist(uri.host), port(uri), %{connect_timeout: 30_000}),
         {:ok, _protocol} <- :gun.await_up(process, :timer.seconds(5)),
         {:ok, _stream_ref} <- ws_upgrade(process, uri.path),
         :ok <- wait_for_ws_upgrade() do
      monitor = Process.monitor(process)

      %__MODULE__{
        process: process,
        monitor: monitor
      }
    else
      error -> error
    end
  end

  def post(message, %{process: process}) do
    :gun.ws_send(process, {:text, message})
  end

  def parse({:gun_ws, _process, _stream_ref, {:text, message}}, state) do
    {[message], state}
  end

  # private
  # ----------------------------------------------------------------------------

  defp port(%{port: port}) when not is_nil(port), do: port
  defp port(%{scheme: "ws"}), do: 80
  defp port(%{scheme: "wss"}), do: 443

  defp wait_for_ws_upgrade do
    receive do
      {:gun_upgrade, _pid, _stream_ref, ["websocket"], _headers} ->
        :ok

      {:gun_response, _pid, _stream_ref, _, status, _headers} ->
        {:error, status}

      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, reason}
    after
      1000 ->
        exit(:timeout)
    end
  end

  # NOTE: We don't yet use persistent browser sessions from the initial
  # launch, so this header is unrelated to the browser type chose during
  # actual execution. It is, however, required that a browser type be
  # provied at launch. So, "chromium" is sent.
  defp ws_upgrade(process, path) do
    headers = [{"x-playwright-browser", "chromium"}]
    {:ok, :gun.ws_upgrade(process, path, headers)}
  end
end

defmodule AsnSocialWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("asn_social.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total repository query time"
      ),
      summary("asn_social.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "PostgreSQL execution time"
      ),
      summary("asn_social.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Connection pool queue time"
      ),
      summary("asn_social.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "Result decode time"
      ),
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total")
    ]
  end

  defp periodic_measurements, do: []
end

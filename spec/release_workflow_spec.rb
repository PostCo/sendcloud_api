# frozen_string_literal: true

require "open3"
require "tempfile"
require "yaml"

RSpec.describe "Release workflow" do
  let(:workflow) { YAML.load_file(File.expand_path("../.github/workflows/release.yml", __dir__)) }
  let(:build) { workflow.fetch("jobs").fetch("build") }
  let(:publish) { workflow.fetch("jobs").fetch("publish") }

  def run_version_check(version, tag)
    script = build.fetch("steps").find { |step| step["id"] == "version" }.fetch("run")[/<<'RUBY'\n(.*)^RUBY$/m, 1]
    Tempfile.create("github-output") do |output|
      _, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3({"RELEASE_TAG" => tag, "GITHUB_OUTPUT" => output.path},
          "ruby", "-e", "module SendcloudAPI; VERSION = #{version.dump}; end; eval($stdin.read)", stdin_data: script)
      end
      [status.success?, stderr.strip, File.read(output.path)]
    end
  end

  it "grants the OIDC token only to a job that runs no repository code" do
    expect(build.fetch("permissions")).to eq("contents" => "read")
    expect(publish.fetch("permissions")).to eq("contents" => "read", "id-token" => "write")
    expect(publish.fetch("needs")).to eq("build")
    expect(publish.fetch("steps").filter_map { |step| step["uses"]&.split("@")&.first }).to eq(
      %w[actions/download-artifact ruby/setup-ruby rubygems/configure-rubygems-credentials]
    )
    expect(publish.fetch("steps").filter_map { |step| step["run"] }).to eq(['gem push "pkg/$GEM_FILE" --host https://rubygems.org'])
  end

  it "keeps the repository, merged-source and tag checks before building the uploaded gem" do
    expect([build["if"], publish["if"]]).to all(eq("github.repository == 'PostCo/sendcloud_api'"))
    runs = build.fetch("steps").filter_map { |step| step["run"] }
    expect(runs.first).to eq("git merge-base --is-ancestor HEAD origin/main")
    expect(runs.last(2)).to eq(["bundle exec rake", "bundle exec rake build"])
    upload = build.fetch("steps").last
    expect(upload["uses"]).to start_with("actions/upload-artifact@")
    expect(upload.dig("with", "name")).to eq(publish.fetch("steps").first.dig("with", "name"))
  end

  it "refuses to release the 0.0.0 scaffold" do
    expect(run_version_check("0.0.0", "v0.0.0")).to eq([false, "Version 0.0.0 is the unreleased scaffold", ""])
  end

  it "requires the tag to match the gem version" do
    expect(run_version_check("0.1.0", "v0.1.1")).to eq([false, "Release tag must match v0.1.0", ""])
    expect(run_version_check("0.1.0", "v0.1.0")).to eq([true, "", "gem_file=sendcloud_api-0.1.0.gem\n"])
  end
end

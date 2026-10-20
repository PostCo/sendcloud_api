# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

RSpec.describe "Release workflow" do
  let(:workflow) { YAML.load_file(File.expand_path("../.github/workflows/release.yml", __dir__)) }
  let(:jobs) { workflow.fetch("jobs") }
  let(:publish_steps) { jobs.fetch("publish").fetch("steps") }
  let(:gem_path_output) { "${{ steps.version.outputs.gem_path }}" }

  def run_version_check(version, tag)
    step = publish_steps.find { |candidate| candidate["id"] == "version" }
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib", "sendcloud_api"))
      File.write(File.join(dir, "lib", "sendcloud_api", "version.rb"), "module SendcloudAPI; VERSION = #{version.dump}; end\n")
      output = File.join(dir, "github-output")
      File.write(output, "")
      _, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3({"RELEASE_TAG" => tag, "GITHUB_OUTPUT" => output}, "bash", "-e", "-c", step.fetch("run"), chdir: dir)
      end
      [status.success?, stderr.strip, File.read(output)]
    end
  end

  it "grants the OIDC token only to the publish job, after tests pass" do
    expect(workflow.fetch("permissions")).to eq("contents" => "read")
    expect(jobs.keys).to eq(%w[test publish])
    expect(jobs.fetch("test").fetch("permissions")).to eq("contents" => "read")
    expect(jobs.fetch("publish").fetch("permissions")).to eq("contents" => "read", "id-token" => "write")
    expect(jobs.fetch("publish").fetch("needs")).to eq("test")
    expect(jobs.values.map { |job| job["if"] }).to all(eq("github.repository == 'PostCo/sendcloud_api'"))
  end

  it "passes nothing from the test job to the publish job" do
    expect(jobs.values.map { |job| job["outputs"] }).to all(be_nil)
    uses = jobs.values.flat_map { |job| job.fetch("steps") }.filter_map { |step| step["uses"] }
    expect(uses).not_to include(a_string_matching(%r{\Aactions/(upload|download)-artifact@}))
  end

  it "builds and pushes from merged source without installing gems or running Bundler" do
    expect(publish_steps.filter_map { |step| step["uses"]&.split("@")&.first }).to eq(
      %w[actions/checkout ruby/setup-ruby rubygems/configure-rubygems-credentials]
    )
    expect(publish_steps.find { |step| step["uses"]&.start_with?("ruby/setup-ruby@") }.fetch("with")).to eq(
      "ruby-version" => "3.3", "bundler" => "none"
    )
    runs = publish_steps.filter_map { |step| step["run"] }
    expect(runs.join("\n")).not_to match(/\bbundle\b|\bgem install\b|\brake\b/)
    expect(runs.first).to eq("git merge-base --is-ancestor HEAD origin/main")
    expect(runs.last(2)).to eq([
      'gem build sendcloud_api.gemspec --output "$GEM_PATH_TO_BUILD"',
      'gem push "$GEM_PATH_TO_PUSH" --host https://rubygems.org'
    ])
    expect(publish_steps.filter_map { |step| step["env"] }.last(2)).to eq([
      {"GEM_PATH_TO_BUILD" => gem_path_output}, {"GEM_PATH_TO_PUSH" => gem_path_output}
    ])
  end

  it "refuses to release the 0.0.0 scaffold" do
    expect(run_version_check("0.0.0", "v0.0.0")).to eq([false, "Version 0.0.0 is the unreleased scaffold", ""])
  end

  it "requires the tag to match the gem version" do
    expect(run_version_check("0.1.0", "v0.1.1")).to eq([false, "Release tag must match v0.1.0", ""])
    expect(run_version_check("0.1.0", "v0.1.0")).to eq([true, "", "gem_path=sendcloud_api-0.1.0.gem\n"])
  end
end

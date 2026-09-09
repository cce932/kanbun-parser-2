# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class LocalEnvironmentTest < Minitest::Test
  def with_local_project
    Dir.mktmpdir("jpmd-local-") do |root|
      FileUtils.cp_r(File.expand_path("../scripts", __dir__), root)
      yield root
    end
  end

  def executable(path, content = "#!/bin/sh\nexit 0\n")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    FileUtils.chmod(0o755, path)
  end

  def test_missing_local_tools_do_not_fall_back_to_path
    with_local_project do |root|
      executable(File.join(root, "global", "ruby"), "#!/bin/sh\necho WRONG_RUBY\n")
      stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{root}/global:#{ENV.fetch('PATH')}" },
        "bash", File.join(root, "scripts/local-exec.sh"), "ruby", "--version"
      )

      refute status.success?
      assert_includes stderr, "setup-local.sh"
      refute_includes stdout, "WRONG_RUBY"
    end
  end

  def test_build_uses_local_tools_and_preserves_arguments_from_other_directory
    with_local_project do |root|
      executable(File.join(root, ".local/runtime/bin/ruby"), <<~SH)
        #!/bin/sh
        printf '%s\\n' "$PWD" "$PANDOC_PATH" "$LUALATEX_PATH" "$GEM_HOME" "$TMPDIR" "$TEXMFCACHE" "$GEM_SPEC_CACHE" "$@"
      SH
      executable(File.join(root, ".local/runtime/bin/pandoc"))
      executable(File.join(root, ".local/texlive/bin/test-platform/lualatex"))

      stdout, stderr, status = Open3.capture3(
        { "PANDOC_PATH" => "/global/pandoc", "LUALATEX_PATH" => "/global/lualatex" },
        "bash", File.join(root, "scripts/build-local.sh"), "my paper.md", "--output", "out/my paper.pdf", chdir: "/"
      )

      assert status.success?, stderr
      assert_equal [
        root, "#{root}/.local/runtime/bin/pandoc",
        "#{root}/.local/texlive/bin/test-platform/lualatex",
        "#{root}/.local/gems", "#{root}/.local/tmp", "#{root}/.local/texmf-var",
        "#{root}/.local/cache/gem-specs", "bin/jpmd", "build", "my paper.md", "--output", "out/my paper.pdf"
      ], stdout.lines.map(&:chomp)
    end
  end
end

# PersonalClaw — Homebrew formula.
#
# WHY THIS FORMULA RESOLVES DEPENDENCIES AT INSTALL TIME instead of vendoring a
# `resource` stanza per dependency (the usual Homebrew idiom for a Python CLI, generated
# by `brew update-python-resources`):
#
# PersonalClaw's runtime closure is ~25 direct dependencies and 60-80 transitively, and
# `virtualenv_install_with_resources` installs every one of them FROM SOURCE with
# `--no-binary :all:`. That closure includes numpy, lxml, cryptography, pypdfium2,
# tree-sitter-language-pack (a very large C build) and two Rust extensions (nh3, rpds-py).
# Vendoring it would mean ~70 hand-maintained stanzas, `depends_on "rust" => :build`, and a
# source build measured in tens of minutes on every install — for a package whose upstream
# publishes pure-Python wheels for all of it.
#
# So the pinned, checksummed artifact here is PersonalClaw's own sdist, and its declared
# dependency bounds — which upper-bound every specifier that has a known-breaking next
# major (see the comments in upstream `pyproject.toml`) — are resolved by pip from PyPI at
# install time with `--prefer-binary`.
#
# The trade-off, stated plainly: this install is NOT hermetic. It needs network during
# `brew install`, and two installs on different days can resolve different dependency
# patch versions. That is exactly the guarantee `pip install personalclaw` gives, which is
# a first-class supported path in upstream's install matrix — this formula wraps it in a
# managed venv, a versioned keg and `brew upgrade`, and does not claim more.
class Personalclaw < Formula
  desc "Self-hosted personal AI agent - chat via Slack, dashboard, or CLI"
  homepage "https://personalclaw.dev"
  # A release bump rewrites THIS url and the sha256 below, and nothing else in the file.
  # The opaque `packages/<a>/<b>/<digest>/` path is mandatory — `brew style`'s
  # FormulaAudit/PyPiUrls cop rejects the predictable `packages/source/p/...` form — so the
  # path cannot be derived from the version by hand. Regenerate both lines with:
  #
  #   curl -s https://pypi.org/pypi/personalclaw/<VERSION>/json \
  #     | python3 -c 'import json,sys; u=[u for u in json.load(sys.stdin)["urls"] \
  #         if u["packagetype"]=="sdist"][0]; \
  #         print(f"""  url "{u["url"]}"\n  sha256 "{u["digests"]["sha256"]}"""")'
  #
  # Deliberately NO `head` spec. A git checkout has no built SPA (`static/dist` is a symlink
  # produced by `make web-build`, which needs Node), so `--HEAD` would install a gateway that
  # serves no dashboard. One install path that works beats two where one is a trap.
  url "https://files.pythonhosted.org/packages/76/ba/0c17014b9a1ac815c97d1fd583ae50445426a033247a374353d5b586c465/personalclaw-0.1.3.tar.gz"
  sha256 "40322c39eceb849908dbf190c7932b58c570dc4a600dba0641697ba210e37f20"
  license "MIT"

  livecheck do
    url :stable
    strategy :pypi
  end

  # Upstream pins `requires-python = ">=3.12,<3.14"`. The upper bound is deliberate, not
  # stale: on 3.14 the connector-pack parse fence refuses every import inside a pack
  # script. 3.13 is the newest interpreter upstream CI verifies, so it is what we build on.
  depends_on "python@3.13"

  def install
    # A dedicated venv under libexec, never the Homebrew site-packages: PersonalClaw
    # installs app bundles' own Python dependencies into its interpreter at runtime
    # (apps/app_manager.py::_install_python_deps), so it needs a writable environment of
    # its own rather than a shared, externally-managed one.
    # `python3.13` resolves from PATH: Homebrew's superenv prepends every declared
    # dependency's bin during install. Reaching through `Formula[...]` for the same binary
    # is what FormulaAudit/FormulaPathMethods objects to, and its replacement helper is too
    # new to assume on every user's brew.
    system "python3.13", "-m", "venv", libexec

    # --prefer-binary: take a published wheel when one exists for this platform and fall
    # back to an sdist only when it does not. Without it pip happily builds numpy and lxml
    # from source and the install takes an order of magnitude longer.
    system libexec/"bin/python", "-m", "pip", "install",
           "--no-cache-dir", "--prefer-binary", buildpath

    bin.install_symlink libexec/"bin/personalclaw"
  end

  def caveats
    <<~EOS
      Next step — create the config home and pick a provider:
        personalclaw setup

      Then start the dashboard on http://localhost:10000:
        personalclaw gateway

      State lives in ~/.personalclaw. Pre-1.0 releases may change its shape without an
      automatic migration, so take a snapshot before upgrading:
        personalclaw snapshot

      This formula resolves PersonalClaw's Python dependencies from PyPI during
      `brew install`, so the install needs network and is not bit-for-bit reproducible.
      See the comment at the top of the formula for why.
    EOS
  end

  test do
    assert_match "personalclaw #{version}", shell_output("#{bin}/personalclaw --version")

    # The CLI must be usable against a throwaway home, never the invoking user's.
    ENV["PERSONALCLAW_HOME"] = testpath/"home"
    assert_match "doctor", shell_output("#{bin}/personalclaw --help")
  end
end

enum CLIHelp {
    static let usage = """
    Usage: TsubameCLI <command> [arguments]

    Commands:
      import <dictionary.zip|directory> [--data-root <path>] [--debug]
          Import a Yomitan dictionary into Tsubame's dictionary library.

      import <dictionary.zip|directory> --dry-run [--debug]
          Run the complete import and validation without keeping the bundle.

      lookup <text> [--data-root <path>] [--debug]
          Look up text from its start in all imported dictionaries.
          Includes Unicode normalization and Japanese deinflection.

      bench lookup <text> [--data-root <path>] [--warmup <count>] [--iterations <count>]
          Benchmark cold and warmed positioned lookup in one process.
          Defaults to 20 warmup and 1000 measured iterations.

      By default, commands use the platform application-data directory.
      --data-root overrides it for development and testing.
    """
}

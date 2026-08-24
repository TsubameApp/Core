enum CLIHelp {
    static let usage = """
    Usage: TsubameCLI <command> [arguments]

    Commands:
      import <dictionary.zip|directory> [--data-root <path>] [--debug]
          Import a Yomitan dictionary into Tsubame's dictionary library.

      import <dictionary.zip|directory> --dry-run [--debug]
          Run the complete import and validation without keeping the bundle.

      lookup <text> [--data-root <path>] [--debug]
          Look up an exact expression or reading in all imported dictionaries.

      By default, commands use the platform application-data directory.
      --data-root overrides it for development and testing.
    """
}

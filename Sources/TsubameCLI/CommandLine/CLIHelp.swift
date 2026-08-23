enum CLIHelp {
    static let usage = """
    Usage: TsubameCLI <command> [arguments]

    Commands:
      import <dictionary.zip|directory>  Extract, parse, and inspect a Yomitan dictionary.
      import <dictionary.zip|directory> --database <path>
                                         Import a Yomitan dictionary into SQLite.
    """
}

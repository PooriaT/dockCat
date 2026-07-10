# URL scheme

Endpoint: `dockcat://notify`.

Parameters: `title` (required, 120 characters), `message` (1,000), `source` (80), `type` (`transient` or `persistent`), `duration` (1–60 seconds), and `action` (optional HTTPS URL, 2,048 characters). Missing type uses transient; missing duration uses the configured default. Invalid input is rejected and never executes commands.

---
description: "Search YouTube and return structured video results"
argument-hint: "<query> [--count N]"
allowed-tools:
  - Bash
---

Run the YouTube search script with the user's arguments and present the results.

Execute this command:

```
python ~/.claude/skills/yt-search/scripts/search.py $ARGUMENTS
```

Present the output directly to the user. If the script reports an error, explain it and suggest fixes.

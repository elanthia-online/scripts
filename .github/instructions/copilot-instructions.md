\# GitHub Copilot Instructions for elanthia-online/scripts



\## Overview

This repository contains shared collaborative Lich scripts (.lic files) that extend the \[Lich-5 scripting engine](https://github.com/elanthia-online/lich-5). Each script should be self-contained while properly utilizing the underlying Lich-5 framework.



\## Scope of Review

\*\*IMPORTANT\*\*: Only review and provide suggestions for code that has been \*\*changed in the current diff/PR\*\*. Do not analyze or comment on unchanged code, even if it appears in the file context.



\## Script Architecture Principles



\### 1. Self-Contained Logic

\- Each .lic script must contain all its own business logic

\- Scripts should be independently executable

\- Avoid cross-script dependencies unless absolutely necessary

\- Keep state management within the script boundaries



\### 2. Lich-5 Engine Integration

All scripts operate within the Lich-5 scripting engine framework. Key integration points:



\#### Core Lich Methods and Objects

\- Use `echo`, `respond`, `\_respond` for output

\- Access game state through `XMLData`, `GameObj`, `Room`, `Char`, etc.

\- Utilize `Script.current`, `Script.run`, `Script.start` for script control

\- Leverage `wait\_while`, `wait\_until`, `waitrt`, `waitcastrt` for timing

\- Use `fput`, `put`, `multifput` for game commands

\- Access settings via `Settings`, `UserVars`, `Vars`



\#### Pattern Matching and Game Data

\- Use `Regexp` patterns with game output appropriately

\- Access room data via `Room.current`, `Room.exits`, etc.

\- Query inventory through `GameObj.inv`, `GameObj.right\_hand`, `GameObj.left\_hand`

\- Check character state with `Char.name`, `Char.skills`, etc.



\#### Script Lifecycle

\- Define cleanup in `before\_dying` hooks

\- Handle script termination gracefully with `kill\_script`

\- Use `pause\_script` and `unpause\_script` appropriately

\- Respect the `Script.current.want\_downstream` flag



\### 3. Ruby Best Practices

\- Follow object-oriented design where appropriate

\- Use meaningful variable and method names

\- Keep methods focused and single-purpose

\- Prefer Ruby idioms (e.g., `each` over `for`, guard clauses)

\- Use blocks and lambdas effectively

\- Handle exceptions appropriately with `begin/rescue/ensure`



\## Code Quality Standards



\### RuboCop Compliance

\*\*All changes must adhere to the RuboCop configuration defined in `.rubocop.yml`\*\* at the repository root.



\#### Before Submitting

\- Run `rubocop -a` to auto-correct style violations

\- Review any remaining violations that require manual fixes

\- Ensure no new RuboCop offenses are introduced



\#### Common Areas of Focus

\- Indentation and spacing (2 spaces, no tabs)

\- Line length limits

\- Method complexity and length

\- Naming conventions (snake\_case for methods/variables, SCREAMING\_SNAKE\_CASE for constants)

\- String literals (prefer single quotes unless interpolation needed)

\- Conditional and loop structures



\### Code Review Priorities (Changed Code Only)

When reviewing changes, focus on:



1\. \*\*Correctness\*\*: Does the change work as intended within Lich-5?

2\. \*\*Self-Containment\*\*: Is all necessary logic present in the script?

3\. \*\*Lich-5 API Usage\*\*: Are Lich methods used correctly and efficiently?

4\. \*\*RuboCop Compliance\*\*: Does the change follow style guidelines?

5\. \*\*Error Handling\*\*: Are edge cases and errors handled appropriately?

6\. \*\*Performance\*\*: Are there obvious performance issues (e.g., infinite loops, excessive polling)?

7\. \*\*Readability\*\*: Is the changed code clear and maintainable?



\## Suggested Change Format



When suggesting improvements, provide:

1\. Clear explanation of the issue in changed code

2\. Specific code suggestion with proper Lich-5 API usage

3\. RuboCop compliance verification (if applicable)

4\. Context about why the change improves the script



Example:

```markdown

The changed loop may cause performance issues:



```ruby

\# Instead of:

loop do

&nbsp; # expensive operation

end



\# Consider:

loop do

&nbsp; # expensive operation

&nbsp; pause 0.1  # Yield to other scripts

end

```



This follows Lich-5 best practices and prevents script from monopolizing execution.

```



\## Common Pitfalls to Avoid (in Changed Code)



1\. \*\*Not yielding in loops\*\*: Use `pause` or `sleep` to yield to other scripts

2\. \*\*Ignoring RuboCop warnings\*\*: Address all style violations in changed code

3\. \*\*Hardcoded values\*\*: Use Settings/UserVars for user-configurable options

4\. \*\*Poor error messages\*\*: Provide clear feedback with `echo` or `respond`

5\. \*\*Resource leaks\*\*: Ensure cleanup in `before\_dying` hooks

6\. \*\*Breaking self-containment\*\*: Avoid dependencies on other .lic scripts

7\. \*\*Incorrect Lich API usage\*\*: Verify methods exist in Lich-5 documentation



\## Script Header Standards



Each script should include appropriate metadata:

```ruby

\# Script Name: scriptname

\# Author: Author Name

\# Version: X.Y.Z

\# Description: Brief description of script functionality

\#

\# Changelog:

\#   X.Y.Z (YYYY-MM-DD): Change description

```



\## Testing Recommendations



Suggest testing approaches for changed code:

\- Verify script starts and stops cleanly

\- Test with various game states

\- Ensure RuboCop passes: `rubocop path/to/changed/script.lic`

\- Check for conflicts with common scripts

\- Validate error handling paths



\## Additional Resources



\- \[Lich-5 Repository](https://github.com/elanthia-online/lich-5) - Core scripting engine

\- \[Repository Wiki](https://github.com/elanthia-online/scripts/wiki) - Additional documentation

\- Ruby Documentation - For Ruby language features



\## Notes for Copilot



\- Focus exclusively on changed lines and their immediate context

\- Do not suggest refactoring unchanged code

\- Prioritize RuboCop compliance for all suggestions

\- Ensure suggestions maintain script self-containment

\- Verify all Lich-5 API usage against engine capabilities

\- Consider the collaborative nature of this repository in suggestions




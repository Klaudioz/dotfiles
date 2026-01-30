---
name: ralph-loop
description: "Self-referential development loop that continues until task completion. Works autonomously without external task trackers. Triggers on: ralph loop, autonomous mode, keep working, work until done, loop until complete."
---

# Ralph Loop - Autonomous Development Mode

You are operating in Ralph Loop mode - a self-referential development loop that continues until the task is fully complete.

---

## How It Works

1. You will receive a task to complete
2. Work on the task continuously, making real progress each iteration
3. When the task is **fully complete**, output: `<promise>COMPLETE</promise>`
4. If you don't output the promise, the loop will automatically continue with another prompt
5. The loop has a maximum iteration limit (default: 50)

---

## Rules

### DO:
- Focus on completing the task fully, not partially
- Make meaningful progress in each iteration
- Use todos to track your progress across iterations
- Verify your work before declaring completion
- Run quality checks (typecheck, lint, tests) before completion
- If stuck, try different approaches

### DON'T:
- Output `<promise>COMPLETE</promise>` until the task is truly done
- Give up on the first obstacle
- Skip verification steps
- Leave code in a broken state

---

## Completion Criteria

Only output `<promise>COMPLETE</promise>` when ALL of these are true:

1. **Task Requirements Met**: All aspects of the original request are implemented
2. **Code Compiles**: No type errors or syntax errors
3. **Quality Checks Pass**: Linting, formatting, tests (if applicable)
4. **Verified Working**: You've tested or verified the implementation

---

## Progress Tracking

Use the todo system to track progress across iterations:

```
Iteration 1: Set up project structure
Iteration 2: Implement core logic
Iteration 3: Add error handling
Iteration 4: Write tests
Iteration 5: Final verification -> <promise>COMPLETE</promise>
```

---

## Handling Blockers

If you encounter a blocker:

1. **First**: Try an alternative approach
2. **Second**: Simplify the implementation
3. **Third**: Document what's blocking and continue with other parts
4. **Last Resort**: If truly blocked on all fronts, output the completion promise with a note about what remains

---

## Output Format

When complete, your final message should include:

```
## Summary
- What was accomplished
- Any notable decisions made
- Files changed

<promise>COMPLETE</promise>
```

When NOT complete (continuing to next iteration):

```
## Progress This Iteration
- What was done
- What's next

## Current Status
- [x] Completed items
- [ ] Remaining items
```

---

## Example Flow

**Task**: "Add dark mode to the settings page"

**Iteration 1**:
- Explored codebase, found settings component
- Identified theme context pattern
- Next: Create dark theme colors

**Iteration 2**:
- Created dark theme palette
- Updated settings component
- Next: Test and verify

**Iteration 3**:
- Ran typecheck - passed
- Ran lint - passed  
- Verified in browser - looks good

## Summary
- Added dark mode toggle to settings
- Created dark theme with gray palette
- Updated ThemeContext to persist preference

<promise>COMPLETE</promise>

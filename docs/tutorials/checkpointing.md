---
layout: tutorial
title: Checkpointing
description: Save crew progress after each task and resume a failed run without repeating finished work
---

# Checkpointing

A checkpoint records what each task produced, so a run that dies partway can resume
without paying for the finished tasks again. It works with the sequential,
hierarchical and consensual processes.

## Save and resume

```ruby
store = RCrewAI::Checkpoint::FileStore.new('.rcrewai/checkpoints')

crew.execute(checkpoint: store)
run_id = crew.run_id # keep this to resume later
```

To resume, build the same crew, with the same task names, and call `resume`:

```ruby
crew.resume(run_id, checkpoint: store)
crew.restored_task_names # => ["research"], the tasks replayed from the checkpoint
```

Completed tasks replay their stored results. Failed tasks are recorded as failed, so
they run again, along with any tasks that never started.

A checkpoint is written each time a task finishes, so a crash loses at most the tasks
still in progress.

## Lineage

A resumed run gets its own `run_id` and links to its parent, which leaves the original
record intact. `lineage` walks the chain from the root:

```ruby
RCrewAI::Checkpoint.lineage(store, crew.run_id)
# => ["<original run id>", "<resumed run id>"]
```

If an ancestor has been deleted, the chain is cut short rather than raising an error.

## Stores

| Store | Use |
|---|---|
| `Checkpoint::FileStore.new(dir)` | One JSON file per run |
| `Checkpoint::MemoryStore.new` | Tests and single-process runs |

Anything responding to `save(id, record)`, `load(id)`, `list` and `delete(id)` works
as a store.

## CLI

```bash
$ rcrewai checkpoint list
$ rcrewai checkpoint info RUN_ID
$ rcrewai checkpoint delete RUN_ID
```

These read `.rcrewai/checkpoints` unless you pass `--dir`.

# FSEvents Partial

Production model: `FilesystemEventRecovery`.

- Partial
- Explicit recovery outcome
- Stored and requested event identifiers
- Dropped user/kernel flags
- Root and volume change flags
- Missing interval
- Fallback baseline result

The interface states that FSEvents locates changes but does not measure byte growth.

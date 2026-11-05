---
applyTo: "**/*.ps1"
---

# Caller Module Discovery

- Resolve an omitted caller module during parameter binding, not in the function body.
- Use `Get-PSCallStack` in the parameter default expression so stack frame `0` is the caller:

```powershell
[Parameter(DontShow)]
[System.String]
$ModuleBase = $(
    $callingModule = ((Get-PSCallStack)[0]).InvocationInfo.MyCommand.Module
    if ($null -ne $callingModule)
    {
        $callingModule.ModuleBase
    }
)
```

- Keep `ModuleBase` overridable for scripts, tests, and hosts without module identity.
- Validate the resolved value and throw an actionable error when no caller module exists.
- Do not move the same lookup into the function body. The callee occupies stack frame `0` there.
- When one helper calls another, capture `ModuleBase` on the outer public function and pass it explicitly to the inner helper.
- For deferred PSU callbacks without module identity, call the reusable helper through a function owned by the consuming module.
- Do not scan every loaded module as a fallback. Multiple modules can expose identical resource names.
- Test automatic discovery through a temporary consumer module that omits `ModuleBase`.
- Test the explicit `ModuleBase` override separately.


# FHL Graph Connector for Public APIs

This sample PowerShell script is part of a Fix Hack Learn (FHL) project to ingest public API data into a [Microsoft Graph connector](https://aka.ms/GraphConnectors).  Data can be used by Microsoft 365 Copilot for reasoning over external data as well as other support experiences (Microsoft Search, Microsoft 365 App, etc.)

> [!NOTE]
> Script and readme are "work in progress".  Please open issues for any suggested changes or fixes.

## Requirements

- [Microsoft PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (currently Windows only)
- [Microsoft.Graph](https://www.powershellgallery.com/packages/Microsoft.Graph) PowerShell module

## Known issues

- Currently only verified supports Windows due to self signed certification.
- Does not check for Microsoft.Graph module and install if needed.
- Application token required to return more than 1000 records, see [docs](https://support.socrata.com/hc/articles/210138558-Generating-an-App-Token) for registering an application token.
- Public API query does not implement paging (i.e. maximum of 1000 records even if supply an app token).

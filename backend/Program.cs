using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

var builder = WebApplication.CreateBuilder(args);

var keyVaultUri = builder.Configuration["KeyVaultUri"];
if (!string.IsNullOrEmpty(keyVaultUri))
{
    try
    {
        builder.Configuration.AddAzureKeyVault(
            new Uri(keyVaultUri),
            new DefaultAzureCredential());
    }
    catch (Exception ex)
    {
        // NOTE: For demo/testing purposes only — in production, consider failing fast on startup
        Console.Error.WriteLine($"[Startup] Key Vault unavailable: {ex.Message}");
    }
}

var app = builder.Build();

app.UseHttpsRedirection();
app.UseStaticFiles();

app.MapGet("/", () => Results.Redirect("/index.html"));

app.MapGet("/api/status", async (IConfiguration config) =>
{
    var vaultUri = config["KeyVaultUri"];
    if (string.IsNullOrEmpty(vaultUri))
        return Results.Ok(new { connected = false });

    try
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var client = new SecretClient(new Uri(vaultUri), new DefaultAzureCredential());
        var secret = await client.GetSecretAsync("status-check", cancellationToken: cts.Token);
        return Results.Ok(new { connected = true, reason = (string?)null, secretValue = secret.Value.Value });
    }
    catch (Azure.RequestFailedException ex)
    {
        var reason = ex.Status == 403
            ? "Key Vault denied access (403 Forbidden) — public network access may be disabled and no approved private link is in use."
            : $"Key Vault request failed ({ex.Status}): {ex.ErrorCode}";
        return Results.Ok(new { connected = false, reason });
    }
    catch (OperationCanceledException)
    {
        return Results.Ok(new { connected = false, reason = "Request timed out — Key Vault may be unreachable (VNet integration not configured or broken)." });
    }
    catch (Exception ex)
    {
        return Results.Ok(new { connected = false, reason = ex.Message });
    }
});

app.Run();

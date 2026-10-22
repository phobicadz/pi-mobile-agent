using HtmlAgilityPack;

if (args.Length < 1)
{
    Console.WriteLine("Usage: WebScraper <url> [output.csv]");
    return;
}

string url = args[0];
string outputPath = args.Length > 1 ? args[1] : "links.csv";

using var httpClient = new HttpClient();
httpClient.DefaultRequestHeaders.UserAgent.ParseAdd(
    "Mozilla/5.0 (compatible; SimpleScraper/1.0)");

Console.WriteLine($"Fetching: {url}");

string html;
try
{
    html = await httpClient.GetStringAsync(url);
}
catch (Exception ex)
{
    Console.WriteLine($"Failed to fetch page: {ex.Message}");
    return;
}

var doc = new HtmlDocument();
doc.LoadHtml(html);

// Extract page title
var title = doc.DocumentNode.SelectSingleNode("//title")?.InnerText.Trim();
Console.WriteLine($"Title: {title}");

// Extract all links
var linkNodes = doc.DocumentNode.SelectNodes("//a[@href]");
var results = new List<(string Text, string Href)>();

if (linkNodes != null)
{
    var baseUri = new Uri(url);

    foreach (var node in linkNodes)
    {
        string href = node.GetAttributeValue("href", "").Trim();
        string text = HtmlEntity.DeEntitize(node.InnerText).Trim();

        if (string.IsNullOrWhiteSpace(href) || href.StartsWith("#") || href.StartsWith("javascript:"))
            continue;

        // Resolve relative URLs to absolute
        if (Uri.TryCreate(baseUri, href, out var absoluteUri))
        {
            results.Add((text, absoluteUri.ToString()));
        }
    }
}

Console.WriteLine($"Found {results.Count} links.");

// Write results to CSV
await using (var writer = new StreamWriter(outputPath))
{
    await writer.WriteLineAsync("Text,Url");
    foreach (var (text, href) in results)
    {
        string safeText = text.Replace("\"", "\"\"");
        string safeHref = href.Replace("\"", "\"\"");
        await writer.WriteLineAsync($"\"{safeText}\",\"{safeHref}\"");
    }
}

Console.WriteLine($"Saved results to {outputPath}");

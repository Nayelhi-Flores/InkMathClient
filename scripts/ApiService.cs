using Godot;
using System;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

using HttpClient = System.Net.Http.HttpClient;

public partial class ApiService : Node
{
    public static ApiService Instance { get; private set; }

    private readonly HttpClient _httpClient = new HttpClient();
    private readonly string _baseUrl = "http://127.0.0.1:5225/api/";
    public string AuthToken { get; set; } = string.Empty;

    public override void _EnterTree()
    {
        if (Instance == null) Instance = this;
        else QueueFree();
    }

    public async Task<(long StatusCode, string ResponseBody)> PostJsonAsync(string endpoint, object payload)
    {
        try
        {
            var json = JsonSerializer.Serialize(payload);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            if (!string.IsNullOrEmpty(AuthToken))
            {
                _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", AuthToken);
            }

            var response = await _httpClient.PostAsync(_baseUrl + endpoint, content);
            string responseBody = await response.Content.ReadAsStringAsync();

            return ((long)response.StatusCode, responseBody);
        }
        catch (Exception ex)
        {
            return (500, JsonSerializer.Serialize(new { mensaje = ex.Message }));
        }
    }

    public async Task<(long StatusCode, string ResponseBody)> PostMultipartAsync(string endpoint, MultipartFormDataContent content)
    {
        try
        {
            string urlCompleta = _baseUrl.TrimEnd('/') + "/" + endpoint.TrimStart('/');

            // Bypassear la validación del certificado SSL autodiseñado para desarrollo local
            var handler = new System.Net.Http.HttpClientHandler
            {
                ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
            };

            using var client = new System.Net.Http.HttpClient(handler);
            
            if (!string.IsNullOrEmpty(AuthToken))
            {
                client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", AuthToken);
            }

            var response = await client.PostAsync(urlCompleta, content);
            string responseBody = await response.Content.ReadAsStringAsync();

            return ((long)response.StatusCode, responseBody);
        }
        catch (Exception ex)
        {
            return (500, JsonSerializer.Serialize(new { mensaje = ex.Message }));
        }
    }
}
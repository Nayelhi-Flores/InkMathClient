using Godot;
using System;
using System.Text.Json;
using System.Text.RegularExpressions;
using Game.Models;

public partial class LoginController : Control
{
    private LineEdit _emailInput;
    private LineEdit _passwordInput;
    private Label _statusLabel;
    private Button _loginButton;

    // Controles de visibilidad de contraseña
    private TextureButton _togglePassButton;
    private Texture2D _eyeOpenTexture;
    private Texture2D _eyeClosedTexture;

    public override void _Ready()
    {
        string basePath = "CenterContainer/PanelContainer/MarginContainer/VBoxContainer/";

        // Cargar texturas SVG idénticas a las del registro
        _eyeOpenTexture = GD.Load<Texture2D>("res://assets/icons/bx-eye.svg");
        _eyeClosedTexture = GD.Load<Texture2D>("res://assets/icons/bx-eye-slash.svg");

        _emailInput = GetNode<LineEdit>(basePath + "EmailInput");
        
        // Configuración de Contraseña
        _passwordInput = GetNode<LineEdit>(basePath + "HBoxContainerPass/PasswordInput");
        _passwordInput.Secret = true;

        _togglePassButton = GetNode<TextureButton>(basePath + "HBoxContainerPass/TogglePassButton");
        _togglePassButton.Pressed += OnTogglePassVisibility;

        if (_eyeClosedTexture != null)
        {
            _togglePassButton.TextureNormal = _eyeClosedTexture;
            _togglePassButton.IgnoreTextureSize = true;
            _togglePassButton.StretchMode = TextureButton.StretchModeEnum.KeepAspectCentered;
        }

        _statusLabel = GetNode<Label>(basePath + "StatusLabel");
        _loginButton = GetNode<Button>(basePath + "LoginButton");

        _loginButton.Pressed += OnLoginPressed;
        GetNode<Button>(basePath + "GoToRegisterButton").Pressed += () => GetTree().ChangeSceneToFile("res://scenes/register.tscn");
    }

    private void OnTogglePassVisibility()
    {
        _passwordInput.Secret = !_passwordInput.Secret;

        if (_eyeOpenTexture != null && _eyeClosedTexture != null)
        {
            _togglePassButton.TextureNormal = _passwordInput.Secret ? _eyeClosedTexture : _eyeOpenTexture;
        }
    }

    private async void OnLoginPressed()
    {
        string email = _emailInput.Text.Trim();
        string pass = _passwordInput.Text;

        // 1. Validación de Correo Electrónico
        string emailPattern = @"^[^@\s]+@[^@\s]+\.[^@\s]+$";
        if (string.IsNullOrWhiteSpace(email) || !Regex.IsMatch(email, emailPattern))
        {
            MostrarStatus("Ingrese una dirección de correo válida.", esError: true);
            _emailInput.GrabFocus();
            return;
        }

        // 2. Validación Básica de Contraseña Vacía
        if (string.IsNullOrWhiteSpace(pass))
        {
            MostrarStatus("Ingrese su contraseña.", esError: true);
            _passwordInput.GrabFocus();
            return;
        }

        // BLOQUEO DE BOTÓN: Previene peticiones duplicadas
        _loginButton.Disabled = true;
        MostrarStatus("Iniciando sesión...", esError: false);

        try
        {
            var requestData = new LoginRequest(email, pass);
            var (statusCode, responseBody) = await ApiService.Instance.PostJsonAsync("Auth/login", requestData);

            if (statusCode == 200 && !string.IsNullOrEmpty(responseBody))
            {
                var response = JsonSerializer.Deserialize<LoginResponse>(responseBody, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                ApiService.Instance.AuthToken = response?.Token ?? string.Empty;

                MostrarStatus("¡Autenticación exitosa!", esError: false);
                GetTree().ChangeSceneToFile("res://scenes/dashboard.tscn");
            }
            else
            {
                _loginButton.Disabled = false;
                
                try
                {
                    var err = JsonSerializer.Deserialize<ErrorResponse>(responseBody, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                    MostrarStatus(err?.Mensaje ?? "Credenciales incorrectas.", esError: true);
                }
                catch
                {
                    MostrarStatus("Error al autenticar con el servidor.", esError: true);
                }
            }
        }
        catch (Exception ex)
        {
            _loginButton.Disabled = false;
            MostrarStatus($"Error de conexión: {ex.Message}", esError: true);
        }
    }

    private void MostrarStatus(string mensaje, bool esError)
    {
        _statusLabel.Text = mensaje;
        _statusLabel.AddThemeColorOverride("font_color", esError ? new Color("#EF4444") : new Color("#10B981"));
    }
}
using Godot;
using System;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using Game.Models;

public partial class RegisterController : Control
{
    private LineEdit _nombreInput;
    private LineEdit _apellidoInput;
    private LineEdit _emailInput;
    private LineEdit _passwordInput;
    
    // Controles de visibilidad de contraseña
    private TextureButton _togglePassButton;
    private Texture2D _eyeOpenTexture;
    private Texture2D _eyeClosedTexture;

    // Labels del Checklist de contraseña
    private Label _lblMinLength;
    private Label _lblUpper;
    private Label _lblNumber;
    private Label _lblSpecial;

    // CheckBox Captcha y adjuntos
    private CheckBox _captchaCheckBox;
    private FileDialog _documentoDialog;
    private Label _selectedFileLabel;
    private Label _statusLabel;
    private Button _registerButton;

    private string _rutaArchivoSeleccionado = string.Empty;

    public override void _Ready()
    {
        string basePath = "CenterContainer/PanelContainer/MarginContainer/VBoxContainer/";

        _eyeOpenTexture = GD.Load<Texture2D>("res://assets/icons/bx-eye.svg");
        _eyeClosedTexture = GD.Load<Texture2D>("res://assets/icons/bx-eye-slash.svg");

        _nombreInput = GetNode<LineEdit>(basePath + "VBoxContainerNombre/NombreInput");
        _apellidoInput = GetNode<LineEdit>(basePath + "VBoxContainerApellido/ApellidoInput");
        _emailInput = GetNode<LineEdit>(basePath + "VBoxContainerEmail/EmailInput");

        // Configuración de Contraseña
        _passwordInput = GetNode<LineEdit>(basePath + "VBoxContainerPass/HBoxContainerPass/PasswordInput");
        _passwordInput.Secret = true;
        _passwordInput.TextChanged += OnPasswordTextChanged;

        _togglePassButton = GetNode<TextureButton>(basePath + "VBoxContainerPass/HBoxContainerPass/TogglePassButton");
        _togglePassButton.Pressed += OnTogglePassVisibility;

        if (_eyeClosedTexture != null)
        {
            _togglePassButton.TextureNormal = _eyeClosedTexture;
            _togglePassButton.IgnoreTextureSize = true;
            _togglePassButton.StretchMode = TextureButton.StretchModeEnum.KeepAspectCentered;
        }

        // Referencias del Checklist (4 Requisitos)
        string checkPath = basePath + "VBoxContainerPass/VBoxContainerPassCheck/";
        _lblMinLength = GetNode<Label>(checkPath + "LblMinLength");
        _lblUpper = GetNode<Label>(checkPath + "LblUpper");
        _lblNumber = GetNode<Label>(checkPath + "LblNumber");
        _lblSpecial = GetNode<Label>(checkPath + "LblSpecial");

        _captchaCheckBox = GetNode<CheckBox>(basePath + "VBoxContainerMFA/CaptchaCheckBox");
        _documentoDialog = GetNode<FileDialog>(basePath + "HBoxContainer/DocumentoDialog");

        _documentoDialog.FileMode = FileDialog.FileModeEnum.OpenFile;
        _documentoDialog.Access = FileDialog.AccessEnum.Filesystem;
        _documentoDialog.UseNativeDialog = true;
        _documentoDialog.Filters = new string[] { "*.pdf, *.jpg, *.jpeg" };

        _selectedFileLabel = GetNode<Label>(basePath + "HBoxContainer/SelectedFileLabel");
        _statusLabel = GetNode<Label>(basePath + "StatusLabel");
        _registerButton = GetNode<Button>(basePath + "RegisterButton");

        GetNode<Button>(basePath + "HBoxContainer/SelectFileButton").Pressed += () => _documentoDialog.PopupCentered();
        _registerButton.Pressed += OnRegisterPressed;
        GetNode<Button>(basePath + "BackButton").Pressed += () => GetTree().ChangeSceneToFile("res://scenes/login.tscn");

        _documentoDialog.FileSelected += OnFileSelected;

        // Evaluación inicial al cargar
        ActualizarChecklist(_passwordInput.Text);
    }

    private void OnTogglePassVisibility()
    {
        _passwordInput.Secret = !_passwordInput.Secret;

        if (_eyeOpenTexture != null && _eyeClosedTexture != null)
        {
            _togglePassButton.TextureNormal = _passwordInput.Secret ? _eyeClosedTexture : _eyeOpenTexture;
        }
    }

    private void OnPasswordTextChanged(string newText)
    {
        ActualizarChecklist(newText);
    }

    private void ActualizarChecklist(string pass)
    {
        bool hasMinLength = pass.Length >= 8;
        bool hasUpper = Regex.IsMatch(pass, "[A-Z]");
        bool hasNumber = Regex.IsMatch(pass, "[0-9]");
        bool hasSpecial = Regex.IsMatch(pass, @"[!@#$%^&*()_+\-=\[\]{};':""\\|,.<>\/?]");

        ActualizarLabelRequisito(_lblMinLength, "Mínimo 8 caracteres", hasMinLength);
        ActualizarLabelRequisito(_lblUpper, "Al menos una mayúscula", hasUpper);
        ActualizarLabelRequisito(_lblNumber, "Al menos un número", hasNumber);
        ActualizarLabelRequisito(_lblSpecial, "Al menos un carácter especial (!@#$%^&*)", hasSpecial);
    }

    private void ActualizarLabelRequisito(Label label, string texto, bool cumplido)
    {
        label.Text = (cumplido ? "✔ " : "• ") + texto;
        label.AddThemeColorOverride("font_color", cumplido 
            ? new Color("#10B981") 
            : new Color("#64748B")
        );
    }

    private void OnFileSelected(string path)
    {
        _rutaArchivoSeleccionado = path;
        _selectedFileLabel.Text = Path.GetFileName(path);
    }

    private async void OnRegisterPressed()
    {
        string nombre = _nombreInput.Text.Trim();
        string apellido = _apellidoInput.Text.Trim();
        string email = _emailInput.Text.Trim();
        string pass = _passwordInput.Text;

        // 1. Validaciones de datos personales (Nombre y Apellido)
        if (string.IsNullOrWhiteSpace(nombre) || nombre.Length < 2)
        {
            MostrarStatus("Ingrese un nombre válido (mínimo 2 caracteres).", esError: true);
            _nombreInput.GrabFocus();
            return;
        }

        if (string.IsNullOrWhiteSpace(apellido) || apellido.Length < 2)
        {
            MostrarStatus("Ingrese un apellido válido (mínimo 2 caracteres).", esError: true);
            _apellidoInput.GrabFocus();
            return;
        }

        // 2. Validación de Correo Electrónico
        string emailPattern = @"^[^@\s]+@[^@\s]+\.[^@\s]+$";
        if (string.IsNullOrWhiteSpace(email) || !Regex.IsMatch(email, emailPattern))
        {
            MostrarStatus("Ingrese una dirección de correo electrónico válida.", esError: true);
            _emailInput.GrabFocus();
            return;
        }

        // 3. Validación Completa de Contraseña
        bool esPasswordValida = pass.Length >= 8 
            && Regex.IsMatch(pass, "[A-Z]") 
            && Regex.IsMatch(pass, "[0-9]")
            && Regex.IsMatch(pass, @"[!@#$%^&*()_+\-=\[\]{};':""\\|,.<>\/?]");

        if (!esPasswordValida)
        {
            MostrarStatus("La contraseña no cumple con los requisitos de seguridad.", esError: true);
            _passwordInput.GrabFocus();
            return;
        }

        // 4. Validación de Archivo Adjunto
        if (string.IsNullOrEmpty(_rutaArchivoSeleccionado))
        {
            MostrarStatus("Debe adjuntar un documento (PDF/JPEG).", esError: true);
            return;
        }

        // 5. Validación de Captcha / MFA Checkbox
        if (!_captchaCheckBox.ButtonPressed)
        {
            MostrarStatus("Por favor, confirma la casilla 'No soy un robot'.", esError: true);
            return;
        }

        // BLOQUEO DE BOTÓN: Deshabilitar inmediatamente para prevenir solicitudes duplicadas
        _registerButton.Disabled = true;
        MostrarStatus("Enviando registro...", esError: false);

        try
        {
            using var content = new MultipartFormDataContent();
            content.Add(new StringContent(nombre), "Nombre");
            content.Add(new StringContent(apellido), "Apellido");
            content.Add(new StringContent(email), "Email");
            content.Add(new StringContent(pass), "Password");

            string generatedToken = $"CAPTCHA_VALIDATED_{Guid.NewGuid().ToString().Substring(0, 8)}";
            content.Add(new StringContent(generatedToken), "MfaToken");

            byte[] fileBytes = File.ReadAllBytes(_rutaArchivoSeleccionado);
            var fileContent = new ByteArrayContent(fileBytes);

            string extension = Path.GetExtension(_rutaArchivoSeleccionado).ToLower();
            string mimeType = extension == ".pdf" ? "application/pdf" : "image/jpeg";
            fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(mimeType);

            content.Add(fileContent, "DocumentoIdentidad", Path.GetFileName(_rutaArchivoSeleccionado));

            var (statusCode, responseBody) = await ApiService.Instance.PostMultipartAsync("Auth/registro", content);

            if (statusCode == 200)
            {
                MostrarStatus("¡Registro exitoso! Redirigiendo...", esError: false);
                await ToSignal(GetTree().CreateTimer(2.0f), SceneTreeTimer.SignalName.Timeout);
                GetTree().ChangeSceneToFile("res://scenes/login.tscn");
            }
            else
            {
                // En caso de error de la API, reactivar el botón para corregir datos
                _registerButton.Disabled = false;
                
                try
                {
                    var err = JsonSerializer.Deserialize<ErrorResponse>(responseBody, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                    MostrarStatus(err?.Mensaje ?? "Error en el registro.", esError: true);
                }
                catch
                {
                    MostrarStatus("Ocurrió un error inesperado en el servidor.", esError: true);
                }
            }
        }
        catch (Exception ex)
        {
            _registerButton.Disabled = false;
            MostrarStatus($"Error de conexión: {ex.Message}", esError: true);
        }
    }

    private void MostrarStatus(string mensaje, bool esError)
    {
        _statusLabel.Text = mensaje;
        _statusLabel.AddThemeColorOverride("font_color", esError ? new Color("#EF4444") : new Color("#10B981"));
    }
}
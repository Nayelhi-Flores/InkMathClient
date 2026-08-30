namespace Game.Models
{
    public record LoginRequest(string Email, string Password);

    public record LoginResponse(
        string Mensaje, 
        long UsuarioId, 
        string Nombre, 
        string Token
    );

    public record ErrorResponse(string Mensaje);
}
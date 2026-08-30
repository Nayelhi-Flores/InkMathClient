using Godot;

public partial class DashboardController : Control
{
    public override void _Ready()
    {
        if (string.IsNullOrEmpty(ApiService.Instance.AuthToken))
        {
            GetTree().ChangeSceneToFile("res://scenes/Login.tscn");
            return;
        }

        GetNode<Button>("MarginContainer/VBoxContainer/LogoutButton").Pressed += OnLogoutPressed;
    }

    private void OnLogoutPressed()
    {
        ApiService.Instance.AuthToken = string.Empty;
        GetTree().ChangeSceneToFile("res://scenes/Login.tscn");
    }
}
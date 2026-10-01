using Microsoft.EntityFrameworkCore;
using Accident_Detection_Backend.Models;
using Accident_Detection_Backend.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Add CORS so iOS app and any frontend can reach the API
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});


//adding location service
builder.Services.AddHttpClient<LocationService>();

// Register push notification service
builder.Services.AddHttpClient<PushNotificationService>();

// Register Dynamic Vehicle Crash Scaling & Edge-Case Engine Configuration
builder.Services.Configure<AccidentDetectionAndAlertSystem.Configuration.CrashScalingConfig>(
    builder.Configuration.GetSection("CrashScaling"));
builder.Services.AddSingleton(sp =>
    sp.GetRequiredService<Microsoft.Extensions.Options.IOptions<AccidentDetectionAndAlertSystem.Configuration.CrashScalingConfig>>().Value);

// Register Crash Analysis & Dynamic Scaling Engine
builder.Services.AddSingleton<AccidentDetectionAndAlertSystem.Services.CrashFilterEngine>();
builder.Services.AddSingleton<AccidentDetectionAndAlertSystem.Services.CrashAnalysisEngine>();



var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseMySql(connectionString, ServerVersion.AutoDetect(connectionString)));

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.UseCors("AllowAll");  // Enable CORS before authorization

app.UseAuthorization();

app.MapControllers();

app.Run();
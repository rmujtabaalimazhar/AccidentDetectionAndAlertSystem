using System.Text.Json;
using Accident_Detection_Backend.Models;

namespace Accident_Detection_Backend.Services
{
    public class LocationService
    {
        private readonly HttpClient _httpClient;
        private readonly string _googleApiKey;
/*
     /   public LocationService(HttpClient httpClient, IConfiguration configuration)
        {
            _httpClient   = httpClient;
            _googleApiKey = configuration["GoogleMaps:ApiKey"]!;
        }
*/
public LocationService(HttpClient httpClient, IConfiguration configuration)
{
    _httpClient   = new HttpClient();
    _googleApiKey = configuration["GoogleMaps:ApiKey"]!;
            _httpClient = httpClient;
        }
        //public async Task<LocationResult?> GetAddressFromCoordinatesAsync(double lat, double lng)
        // {
        //     var url = $"https://maps.googleapis.com/maps/api/geocode/json?latlng={lat},{lng}&key={_googleApiKey}";

        //     var response = await _httpClient.GetAsync(url);
        //     if (!response.IsSuccessStatusCode) return null;

        //     var json = await response.Content.ReadAsStringAsync();
        //     var doc  = JsonDocument.Parse(json);
        //     var root = doc.RootElement;

        //     if (root.GetProperty("status").GetString() != "OK") return null;

        //     var results = root.GetProperty("results");
        //     if (results.GetArrayLength() == 0) return null;

        //     var firstResult     = results[0];
        //     var formattedAddress = firstResult.GetProperty("formatted_address").GetString();

        //     // Extract city and country from address_components
        //     string? city    = null;
        //     string? country = null;

        //     foreach (var component in firstResult.GetProperty("address_components").EnumerateArray())
        //     {
        //         var types = component.GetProperty("types");
        //         bool isLocality = false, isCountry = false;

        //         foreach (var type in types.EnumerateArray())
        //         {
        //             if (type.GetString() == "locality")       isLocality = true;
        //             if (type.GetString() == "country")        isCountry  = true;
        //         }

        //         if (isLocality) city    = component.GetProperty("long_name").GetString();
        //         if (isCountry)  country = component.GetProperty("long_name").GetString();
        //     }

        //     return new LocationResult
        //     {
        //         Latitude         = lat,
        //         Longitude        = lng,
        //         FormattedAddress = formattedAddress,
        //         City             = city,
        //         Country          = country
        //     };
        // }
        public async Task<LocationResult?> GetAddressFromCoordinatesAsync(double lat, double lng)
{
    // TEMPORARY TEST
    return new LocationResult
    {
        Latitude         = lat,
        Longitude        = lng,
        FormattedAddress = "Test Address, Rawalpindi",
        City             = "Rawalpindi",
        Country          = "Pakistan"
    };
}
    }
}

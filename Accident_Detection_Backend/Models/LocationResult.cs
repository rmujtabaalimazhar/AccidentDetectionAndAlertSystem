namespace Accident_Detection_Backend.Models
{
    public class LocationResult
    {
        public double Latitude       { get; set; }
        public double Longitude      { get; set; }
        public string? Address       { get; set; }
        public string? City          { get; set; }
        public string? Country       { get; set; }
        public string? FormattedAddress { get; set; }
    }
}


using System.ComponentModel.DataAnnotations;

namespace Accident_Detection_Backend.Models
{
    public class AccidentRequest
    {
        [Required]
        public int CarId { get; set; }

        // Fallback for snake_case JSON requests (e.g. Car_Id)
        public int? Car_Id
        {
            get => CarId;
            set { if (value.HasValue && value.Value > 0) CarId = value.Value; }
        }

        public string? AccidentType { get; set; }
        public string? ImpactSide { get; set; }
        public string? SteeringSide { get; set; }
        public string? Steering_Side
        {
            get => SteeringSide;
            set { if (!string.IsNullOrWhiteSpace(value)) SteeringSide = value; }
        }
        public string? Severity { get; set; }
        public DateTime? Time { get; set; }

        // Linear Acceleration Vectors
        public double Acceleration { get; set; }
        public double AccelX { get; set; }
        public double AccelY { get; set; }
        public double AccelZ { get; set; }

        // Gyroscope data
        public double GyroX { get; set; }
        public double GyroY { get; set; }
        public double GyroZ { get; set; }

        // Location info
        public string? Location { get; set; }
        public double Latitude { get; set; }
        public double Longitude { get; set; }
    }
}
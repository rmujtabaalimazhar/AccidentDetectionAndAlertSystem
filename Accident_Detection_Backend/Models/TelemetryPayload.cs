using System;

namespace Accident_Detection_Backend.Models
{
    public class TelemetryPayload
    {
        public string? UserId { get; set; }
        public int? CarId { get; set; }
        public double AccelX { get; set; }
        public double AccelY { get; set; }
        public double AccelZ { get; set; }
        public double GyroX { get; set; }
        public double GyroY { get; set; }
        public double GyroZ { get; set; }
        public double ImpactDurationMs { get; set; }
        public int ImpactNode { get; set; } = 1;
    }
}

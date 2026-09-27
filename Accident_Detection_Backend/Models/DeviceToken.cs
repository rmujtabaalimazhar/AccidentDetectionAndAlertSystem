using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Accident_Detection_Backend.Models
{
    [Table("DeviceTokens")]
    public class DeviceToken
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        [StringLength(255)]
        public string UserIdentifier { get; set; } = null!; // User UID (or guardian email) or Rescue Rid (e.g. "1")

        [Required]
        [StringLength(50)]
        public string UserType { get; set; } = "Guardian"; // "Guardian", "Rescue", "Driver"

        [Required]
        [StringLength(512)]
        public string Token { get; set; } = null!; // APNs device token or push identifier

        [StringLength(50)]
        public string Platform { get; set; } = "iOS";

        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}

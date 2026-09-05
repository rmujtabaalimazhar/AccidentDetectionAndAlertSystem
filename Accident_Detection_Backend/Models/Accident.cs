using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Accident_Detection_Backend.Models
{
  [Table("Accident")]
    public class Accident
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Accident_Id { get; set; }

        [Required]
        public int Car_Id { get; set; }

        [StringLength(255)]
        public string? Location { get; set; }

        [StringLength(50)]
        public string? Impact_Side { get; set; }

        [Column(TypeName = "decimal(10,2)")]
        public decimal? ImpactForce { get; set; }

        [Column(TypeName = "decimal(10,2)")]
        public decimal? CabinForce { get; set; }

        // Timestamp of when the accident was recorded
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // Navigation Property
        [ForeignKey("Car_Id")]
        public Car Car { get; set; } = null!;
    }
}

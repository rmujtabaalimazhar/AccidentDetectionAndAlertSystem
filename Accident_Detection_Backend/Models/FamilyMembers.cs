using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Accident_Detection_Backend.Models
{
    [Table("FamilyMembers")]
    public class FamilyMembers
    {
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Family_Id { get; set; }

        [Required]
        [StringLength(255)]
        public string Uid { get; set; } = null!;

        [Required]
        [StringLength(255)]
        public string Guardian_Id { get; set; } = null!;

        [Required]
        [StringLength(50)]
        public string Relationship { get; set; } = null!;

        // Navigation properties
        [ForeignKey("Uid")]
        [JsonIgnore]
        public virtual User? User { get; set; }

        [ForeignKey("Guardian_Id")]
        [JsonIgnore]
        public virtual User? Guardian { get; set; }
    }
}

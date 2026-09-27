using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Accident_Detection_Backend.Models
{
    [Table("Rescue")]
    public class Rescue
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Rid { get; set; }

        [Required]
        [StringLength(255)]
        public string Password { get; set; } = null!;

        [StringLength(255)]
        public string? Location { get; set; }
    }
}

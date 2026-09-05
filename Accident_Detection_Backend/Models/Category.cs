using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Accident_Detection_Backend.Models
{
    [Table("Category")]
    public class Category
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Category_Id { get; set; }

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = null!;

        [Column(TypeName = "decimal(10,2)")]
        public decimal? Weight { get; set; }

        // Navigation Properties
        public ICollection<Car>   Cars  { get; set; } = new List<Car>();
        public ICollection<Nodes> Nodes { get; set; } = new List<Nodes>();
    }
}
# Products Sheet — Initial Catalog

Paste these rows into the **Products** tab (after the header row). Leave
`Timestamp` blank — it auto-fills when entered via the Form, or leave blank
if pasting directly into the Sheet.

`Current Selling Price` and `Reorder Level` are intentionally **left blank**
— these weren't in the source PDF (which showed sales totals, not unit
prices) and shouldn't be guessed. Fill them in before running `dbt run`,
since `stg_products` drops any row with no valid selling price > 0.

Three items are flagged `[CONFIRM]` — the exact product meaning was unclear
from the PDF; rename if needed before pasting.

| Product Name | Category | Unit of Measure | Current Selling Price | Reorder Level | Active |
|---|---|---|---|---|---|
| Grass | Flooring | Sq Metre | | 5 | Yes |
| Carpet | Flooring | Sq Metre | | 5 | Yes |
| Tiles carpet | Flooring | Sq Metre | | 5 | Yes |
| SPC | Flooring | Sq Metre | | 5 | Yes |
| Interlocking | Flooring | Sq Metre | | 5 | Yes |
| LVT | Flooring | Sq Metre | | 5 | Yes |
| Coin mat | Flooring | Piece | | 5 | Yes |
| Mkeka ya mbao | Flooring | Piece | | 5 | Yes |
| Poly car [CONFIRM] | Flooring | Sq Metre | | 5 | Yes |
| Blinds | Window Treatments | Piece | | 5 | Yes |
| Rods | Window Treatments | Piece | | 5 | Yes |
| Rails | Window Treatments | Piece | | 5 | Yes |
| Curtains | Window Treatments | Pair | | 5 | Yes |
| Films | Window Treatments | Roll | | 5 | Yes |
| Privacies | Window Treatments | Roll | | 5 | Yes |
| Wallpapers | Wall & Ceiling Decor | Roll | | 5 | Yes |
| Wall panels | Wall & Ceiling Decor | Piece | | 5 | Yes |
| 3D panels | Wall & Ceiling Decor | Piece | | 5 | Yes |
| Acrylic | Wall & Ceiling Decor | Piece | | 5 | Yes |
| Partition | Wall & Ceiling Decor | Piece | | 5 | Yes |
| Fluted panels | Wall & Ceiling Decor | Piece | | 5 | Yes |
| Marble sheet | Wall & Ceiling Decor | Piece | | 5 | Yes |
| Shower curtains | Bathroom & Balcony | Piece | | 5 | Yes |
| Balc shield [CONFIRM] | Bathroom & Balcony | Piece | | 5 | Yes |
| Loose covers | Home Accessories | Set | | 5 | Yes |
| Trunk storage | Home Accessories | Piece | | 5 | Yes |
| Leather bag | Home Accessories | Piece | | 5 | Yes |
| Ceramic vase | Home Accessories | Piece | | 5 | Yes |
| Metallic vase | Home Accessories | Piece | | 5 | Yes |
| Watch organiser | Home Accessories | Piece | | 5 | Yes |
| Locks | Hardware & Fixings | Piece | | 5 | Yes |
| Glue | Hardware & Fixings | Piece | | 5 | Yes |
| Spaghetti n perf [CONFIRM] | Hardware & Fixings | Piece | | 5 | Yes |

## Updating the Google Form dropdowns

After confirming this list, update the **Product** dropdown options on:
- Sales Entry form
- Inventory Purchase form
- Returns Entry form

to exactly match these 32 product names (the `product_key` join across all
staging models is a slugified version of whatever name is typed here, so
consistent spelling matters more than exact casing).

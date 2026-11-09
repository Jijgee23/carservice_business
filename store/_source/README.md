# Store assets source

Headless Chrome renders `template.html` (carservice.mn "Midnight + Alizarin" palette, Geist font, brand SVGs from `carcare.mn/public/brand`).

```sh
# render.sh <out.png> <css-width> <css-height> <scale> "<query>"
./render.sh ../appstore_header.png        1920 823  2 "kind=hero&app=customer"
./render.sh ../appstore_search_result.png 1920 1280 2 "kind=hero&app=customer"
./render.sh ../play_feature_graphic.png   1024 500  1 "kind=feature&app=customer"
./render.sh ../logo/logo_light.png        1200 300  2 "kind=logo&app=customer&tone=light"
./render.sh ../logo/logo_dark.png         1200 300  2 "kind=logo&app=customer&tone=dark"
./render.sh ../logo/mark.png              512  512  2 "kind=mark"
```
`app=customer` | `app=business`. Logo PNGs were trimmed to content + 12% padding afterwards. Icons (`appstore_icon_1024.png`, `play_icon_512.png`) are the launcher icon source flattened on white (no alpha).

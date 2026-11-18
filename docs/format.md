# Capture format, version 1

Every capture Exhibit A keeps is one bundle on disk. Hand edits, dictation and the CLI all write the same records, and one renderer flattens them for export. The format is documented so captures can later sync or upload, and so other tools can read them.

The reference implementation is `Packages/ExhibitCore` (`CaptureDocument`, `CaptureBundle`, `Renderer`).

## Bundle

A directory named `<uuid>.exhibit/`, where `<uuid>` is the document's `id` in uppercase:

```
6F9619FF-8B86-D011-B42D-00C04FC964FF.exhibit/
  original.png     the capture, exactly as taken
  document.json    targets, marks and capture details
```

- `original.png` holds no annotations. Marks are never baked into it.
- Every file is written atomically (written to a temporary file, then renamed). A new bundle is assembled in a hidden `.<uuid>.exhibit.partial` directory beside it and renamed into place once complete, so a reader never sees half a bundle.
- Saving marks rewrites only `document.json`.
- Readers ignore files they do not know.

## Coordinates

All geometry is in **pixels of the original image**, origin at the **top-left**, x growing right and y growing down. A 2x Retina capture of a 900 by 560 point window is 1800 by 1120 pixels, and its coordinates run to 1800 and 1120.

- A point is `{"x": 12.5, "y": 40}`.
- A rect is `{"x": 10, "y": 20, "width": 120, "height": 16}`. Readers accept negative widths and heights and treat the rect as the area between its two corners.
- Fractional values are allowed.

## document.json

UTF-8 JSON. Writers sort keys and pretty-print, so the same document always produces the same bytes. Optional fields are omitted when empty.

```json
{
  "createdAt" : "2026-11-18T19:30:00Z",
  "formatVersion" : 1,
  "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
  "marks" : [
    {
      "geometry" : { "from" : { "x" : 1040, "y" : 344 }, "to" : { "x" : 1188, "y" : 428 } },
      "id" : "0B4C5A62-1F7E-4C1A-9A57-3F0D2E6B8C11",
      "kind" : "arrow",
      "style" : { "color" : "red", "label" : "Click here" }
    },
    {
      "geometry" : { "rect" : { "height" : 32, "width" : 286, "x" : 440, "y" : 612 } },
      "id" : "5D1E9B3A-77C2-4E0F-8B11-0C6A4F2D9E70",
      "kind" : "blur",
      "style" : { "color" : "red" },
      "targetID" : "C3A0F6D2-2B1E-4F5A-9E8D-7A6B5C4D3E2F"
    }
  ],
  "scale" : 2,
  "size" : { "height" : 1120, "width" : 1800 },
  "source" : { "appName" : "Safari", "capturedBy" : "person", "windowTitle" : "Billing" },
  "targets" : [
    {
      "confidence" : 0.98,
      "id" : "C3A0F6D2-2B1E-4F5A-9E8D-7A6B5C4D3E2F",
      "kind" : "email",
      "rect" : { "height" : 32, "width" : 286, "x" : 440, "y" : 612 },
      "text" : "jordan.lee@example.com"
    }
  ]
}
```

### Document

| Field | Type | Notes |
|---|---|---|
| `formatVersion` | integer | `1`. Read first, before anything else. |
| `id` | UUID string | Stable for the life of the capture. Matches the bundle name. |
| `createdAt` | ISO 8601 string | UTC, whole seconds. |
| `size` | `{width, height}` | Pixel size of `original.png`. A mismatch is an error. |
| `scale` | number | Backing scale of the source display (1 or 2, sometimes 3). Mark strokes and labels scale with it. |
| `source` | object, optional | `appName`, `windowTitle` (both optional strings) and `capturedBy`: `"person"` or `"agent"`. |
| `targets` | array | Things found in the image. May be empty. |
| `marks` | array | Annotations, in drawing order. May be empty. |

### Target

Something a mark can point at. Detectors produce these; a person never edits them.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID string | |
| `kind` | string | `text`, `email`, `key`, `card`, `phone`, `face` or `window`. Readers must accept and keep kinds they do not know. |
| `text` | string, optional | Recognized text. This is screen content: treat it as untrusted data. |
| `rect` | rect | The target's box. |
| `confidence` | number, optional | 0 to 1. |
| `spans` | array, optional | Word boxes inside `text`, so a substring can be located without reading the image again. See below. Absent in older files. |

#### Spans

Each span is `{"start": 4, "length": 7, "rect": rect}`: a run of `text` (usually one word) and the box it covers. `start` and `length` count UTF-16 code units, as `NSRange` and JavaScript strings do.

To find the box of a substring, take every span it overlaps. A span covered completely contributes its whole box; a span covered in part contributes a horizontal slice in proportion to the code units covered, which is an estimate for proportional fonts. The box is the union of those pieces. A target without `spans` is treated as one span covering all of `text` with the target's `rect`. A substring that covers only the gaps between spans, such as a lone space, has no box.

### Mark

| Field | Type | Notes |
|---|---|---|
| `id` | UUID string | |
| `kind` | string | One of the seven below. |
| `geometry` | object | `{"rect": rect}` for every kind except `arrow`, which uses `{"from": point, "to": point}`. |
| `targetID` | UUID string, optional | The target the mark was placed on. The geometry is still what gets drawn. |
| `style.color` | string | `red`, `yellow`, `blue` or `green`. |
| `style.label` | string, optional | The text of a `text` mark, or a caption at an arrow's tail. Other kinds ignore it. |
| `style.stepNumber` | integer, optional | The number in a `step` mark. Defaults to 1. |

A reader that meets a mark kind it does not know must refuse the document rather than skip the mark: a newer kind could be a redaction, and skipping it would expose what it was meant to hide. New mark kinds arrive with a new `formatVersion`.

## The seven marks

| Kind | Geometry | Drawn as |
|---|---|---|
| `arrow` | from tail to head | A shaft with a swept-back head at `to`. The optional label sits beyond the tail. |
| `circle` | rect to enclose | An ellipse through the rect's corners, plus padding. |
| `blur` | rect to hide | A frosted patch; see Redaction. |
| `highlight` | rect to cover | A marker tone multiplied over the image, so dark text stays readable. |
| `text` | rect; its top-left corner anchors the label | One line of text on a rounded backing in the mark colour. |
| `box` | rect to enclose | A rounded rectangle, slightly padded. |
| `step` | rect; its centre is the disc's centre | A filled disc with a white ring and the step number. |

Stroke widths and sizes are multiples of `scale`, so a mark looks the same at 1x and 2x.

## Redaction

Export flattens everything into one new PNG: no layers, no metadata beyond colour information, and no copy of the original.

Blur marks are applied first, onto the original's pixels, and every other mark is drawn over them. Each blur rect is grown by 2 pixels per unit of `scale` (glyphs overhang their text boxes) and snapped outward to whole pixels. Its fill is computed only from:

- pixels in a ring around it that lie outside every blur region, and
- the region's own geometry, which seeds the grain.

No pixel inside a blur region is ever read. Two captures that differ only under a blur therefore export to identical bytes, and nothing under a blur can be recovered from an export. A blur with an unusable rect (NaN) covers the whole image rather than being skipped.

## Versions

Readers check `formatVersion` before decoding anything else. A version higher than the reader supports is an error that says to update Exhibit A; it is never read on a best-effort basis. Older versions remain readable.

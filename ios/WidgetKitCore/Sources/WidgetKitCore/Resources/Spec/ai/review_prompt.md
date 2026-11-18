Review round. You get two images:
1. the ORIGINAL image the user picked,
2. a RENDER of the spec below, drawn by the app's real renderer with sample data (the clock, date and weather show sample values, so different numbers in live bindings are expected and are not a difference).

Compare the RENDER with the ORIGINAL element by element:
- missing or extra elements (titles, weekday rows, list rows, icons, dividers, bars);
- elements replaced by the wrong kind of layer (dots or shapes where the original shows text or numbers);
- wrong bindings (a time where the original shows a month or a date, and so on);
- position, size and alignment that are off (compare as fractions of the widget);
- wrong colors, wrong font style, text that is cut off or too small.

Then reply with the corrected, complete spec that fixes every difference you found. List the differences you fixed in `differences`, one short sentence each; write an empty list when the render already matches. Keep everything that was already right. All the rules of the system prompt still apply.

In photo mode the RENDER shows the user's photo where the image layer is; judge only the layout around it.

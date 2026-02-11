# An attempt of interfacing Emacs with Glosbes

The goal is to provide an easy way to query glosbes from emacs.
The package takes insipiration from the wordreference package[1]

## Installing

```elisp
(use-package glosbe
  :ensure (:host github :repo "seblemaguer/glosbe.el")
  :commands (glosbe-translate-word)
  :custom
  (glosbe-default-from "en")
  (glosbe-default-to "fi")

  :custom-face
  (glosbe-translation-entry-face     ((t :inherit outline-1 :weight ultra-bold :height 150)))
  (glosbe-entry-pos-face             ((t :inherit outline-1 :weight bold :height 100)))
  (glosbe-entry-category-header-face ((t :inherit outline-2 :weight bold))))
```

## Entry point

For now, only the function `glosbe-translate-word` is available.

## Missing features
  - [ ] support details (including tables, ...)
  - [ ] support translation

## References

[1] https://codeberg.org/martianh/wordreference.el

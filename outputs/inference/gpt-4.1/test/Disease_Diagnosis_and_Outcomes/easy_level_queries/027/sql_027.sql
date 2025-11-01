with hemorrhage%'
    OR LOWER(dd.long_title) LIKE '%hemorrhagic gastritis%'
    OR LOWER(dd.long_title) LIKE '%gastric ulcer with hemorrhage%'
    OR LOWER(dd.long_title) LIKE '%duodenal ulcer with hemorrhage%'
    OR LOWER(dd.long_title) LIKE '%esophageal varices with hemorrhage%'
    OR LOWER(dd.long_title) LIKE '%mallory-weiss syndrome%'
    OR LOWER(dd.long_title) LIKE '%hematemesis%'
  )
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 49 AND 59
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
;
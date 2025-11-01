AND (
  (d1d.long_title ILIKE '%diabetes mellitus, type 2%' OR d1d.long_title ILIKE '%type 2 diabetes%')
  AND
  (d2d.long_title ILIKE '%heart failure%' OR d2d.long_title ILIKE '%congestive heart failure%')
);
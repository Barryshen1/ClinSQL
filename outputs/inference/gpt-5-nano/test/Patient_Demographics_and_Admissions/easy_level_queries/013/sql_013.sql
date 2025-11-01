SELECT
  MAX(DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY)) AS max_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
WHERE
  (LOWER(p.gender) = 'm' OR LOWER(p.gender) = 'male')
  AND p.anchor_age IS NOT NULL
  AND p.anchor_year IS NOT NULL
  -- Age at admission: approximate birth year = anchor_year - anchor_age
  AND DATE_DIFF(DATE(a.admittime), DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 58 AND 68
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;
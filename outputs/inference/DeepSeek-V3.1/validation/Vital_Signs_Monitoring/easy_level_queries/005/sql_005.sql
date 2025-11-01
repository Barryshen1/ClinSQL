SELECT
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS systolic_bp_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ce.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND ce.itemid IN (220179, 220050)  -- Systolic BP itemids
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND ce.valuenum < 300;  -- Reasonable range for systolic BP;
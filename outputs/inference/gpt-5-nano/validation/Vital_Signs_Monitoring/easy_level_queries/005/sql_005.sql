SELECT
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(74)] AS p75_systolic_bp
FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON ce.itemid = di.itemid
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON ce.subject_id = p.subject_id
WHERE ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND LOWER(di.label) LIKE '%systolic%'
  AND LOWER(di.label) LIKE '%blood%pressure%'
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69;
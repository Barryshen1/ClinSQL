SELECT
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS systolic_bp_75th_percentile
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_icu.chartevents ce
  ON p.subject_id = ce.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.d_items di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND di.category = 'Vital Signs'
  AND LOWER(di.label) LIKE '%systolic%'
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum BETWEEN 50 AND 250;
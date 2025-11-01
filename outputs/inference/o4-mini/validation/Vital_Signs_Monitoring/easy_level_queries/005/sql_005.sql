SELECT
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS sbp_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ce.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND LOWER(di.label) LIKE '%systolic blood pressure%'
  AND ce.valuenum IS NOT NULL;
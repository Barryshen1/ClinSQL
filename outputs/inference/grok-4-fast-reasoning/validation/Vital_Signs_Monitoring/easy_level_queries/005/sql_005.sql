SELECT
  APPROX_QUANTILES(ce.valuenum, 4)[OFFSET(3)] AS p75_systolic_bp
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` ic
  ON ce.subject_id = ic.subject_id
  AND ce.hadm_id = ic.hadm_id
  AND ce.stay_id = ic.stay_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ic.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND LOWER(di.label) LIKE '%systolic blood pressure%'
  AND ce.valuenum IS NOT NULL;
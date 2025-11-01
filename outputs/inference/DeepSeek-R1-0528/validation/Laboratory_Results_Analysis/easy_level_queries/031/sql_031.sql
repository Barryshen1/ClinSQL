SELECT
  APPROX_QUANTILES(l.valuenum, 100)[OFFSET(75)] AS potassium_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` i
  ON a.hadm_id = i.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON a.hadm_id = l.hadm_id
  AND a.subject_id = l.subject_id
WHERE
  p.gender = 'M'
  AND l.itemid = 50822  -- Serum potassium in blood
  AND l.valuenum IS NOT NULL
  AND DATE(l.charttime) = DATE(a.dischtime);
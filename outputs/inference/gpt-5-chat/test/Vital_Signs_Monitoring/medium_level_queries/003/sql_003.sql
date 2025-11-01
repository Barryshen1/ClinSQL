WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.anchor_age,
    pat.gender,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 71 AND 81
),
temps_first48 AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_temp_48h
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
   AND ce.itemid IN (223761, 676) -- Temperature (Celsius)
   AND ce.valuenum IS NOT NULL
   AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
mi_flags AS (
  SELECT DISTINCT
    hadm_id,
    1 AS mi_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9  AND STARTS_WITH(icd_code, '410'))
     OR (icd_version = 10 AND STARTS_WITH(icd_code, 'I21'))
),
joined AS (
  SELECT
    t.stay_id,
    c.hadm_id,
    t.avg_temp_48h,
    CASE
      WHEN t.avg_temp_48h < 36.0 THEN '<36.0'
      WHEN t.avg_temp_48h < 38.0 THEN '36.0-37.9'
      ELSE '>=38.0'
    END AS temp_cat,
    IF(mf.mi_flag IS NOT NULL, 1, 0) AS mi_flag
  FROM temps_first48 t
  JOIN cohort c
    ON t.stay_id = c.stay_id
  LEFT JOIN mi_flags mf
    ON c.hadm_id = mf.hadm_id
)
SELECT
  temp_cat,
  COUNT(*) AS n_stays,
  AVG(avg_temp_48h) AS mean_temp,
  APPROX_QUANTILES(avg_temp_48h, 2)[OFFSET(1)] AS median_temp,
  (APPROX_QUANTILES(avg_temp_48h, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_temp_48h, 4)[OFFSET(1)]) AS iqr_temp,
  AVG(mi_flag) AS mi_rate
FROM joined
GROUP BY temp_cat
ORDER BY temp_cat;
WITH population AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    adm.admittime,
    adm.deathtime,
    adm.hospital_expire_flag,
    CASE WHEN adm.deathtime IS NOT NULL OR adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS died,
    pat.anchor_age,
    pat.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = icu.subject_id
  WHERE LOWER(pat.gender) IN ('f', 'female')
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 81 AND 91
),
temperature_per_stay AS (
  SELECT
    p.hadm_id,
    p.stay_id,
    AVG(ce.valuenum) AS mean_temp
  FROM population AS p
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.stay_id = p.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE ce.charttime >= p.intime
    AND ce.charttime <= TIMESTAMP_ADD(p.intime, INTERVAL 24 HOUR)
    AND LOWER(di.label) LIKE '%temperature%'
    AND ce.valuenum IS NOT NULL
  GROUP BY p.hadm_id, p.stay_id
)
SELECT
  CASE
    WHEN t.mean_temp < 36.0 THEN '<36.0'
    WHEN t.mean_temp >= 36.0 AND t.mean_temp <= 37.9 THEN '36.0-37.9'
    WHEN t.mean_temp >= 38.0 THEN '≥38.0'
  END AS temperature_group,
  COUNT(*) AS N,
  AVG(t.mean_temp) AS mean_temperature,
  APPROX_QUANTILES(t.mean_temp, 100)[OFFSET(50)] AS median_temperature,
  (APPROX_QUANTILES(t.mean_temp, 100)[OFFSET(75)] - APPROX_QUANTILES(t.mean_temp, 100)[OFFSET(25)]) AS iqr_temperature,
  SUM(p.died) AS deaths,
  (SUM(p.died) / CAST(COUNT(*) AS FLOAT64)) * 100 AS mortality_rate_percent
FROM temperature_per_stay AS t
JOIN population AS p
  ON p.hadm_id = t.hadm_id
 AND p.stay_id = t.stay_id
GROUP BY temperature_group
ORDER BY temperature_group;
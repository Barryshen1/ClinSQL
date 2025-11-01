WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND a.hadm_id NOT IN (
      SELECT DISTINCT hadm_id 
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE hadm_id IS NOT NULL
    )
),
stratified AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'hospice'
      ELSE NULL
    END AS discharge_stratum,
    los_days
  FROM patient_admissions
  WHERE discharge_location IS NOT NULL
    AND (hospital_expire_flag = 1 OR discharge_location IN ('HOME') OR discharge_location LIKE 'HOSPICE%')
)
SELECT
  discharge_stratum,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(950)] AS p95_los,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank_7day
FROM stratified
WHERE discharge_stratum IS NOT NULL
GROUP BY discharge_stratum
ORDER BY discharge_stratum;
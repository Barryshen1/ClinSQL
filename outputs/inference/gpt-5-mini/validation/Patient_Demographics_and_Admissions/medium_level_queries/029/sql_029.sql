WITH icu_hadm AS (
  -- hospital admission ids that had any ICU stay
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE hadm_id IS NOT NULL
),

female_icu_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN icu_hadm i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
    ELSE 'discharged alive'
  END AS survival,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days < 7 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_los_lt_7_days
FROM (
  SELECT
    *,
    -- fractional LOS in days
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM female_icu_adms
)
GROUP BY survival
ORDER BY survival DESC;
WITH icu_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.discharge_location,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
    -- Calculate age at admission
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 63 AND 73
),
outcome_groups AS (
  SELECT
    stay_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM icu_ages
  WHERE hospital_expire_flag = 1
     OR LOWER(discharge_location) LIKE '%hospice%'
     OR LOWER(discharge_location) LIKE '%home%'
)
SELECT
  discharge_outcome,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_le_10_days
FROM outcome_groups
GROUP BY discharge_outcome
ORDER BY discharge_outcome;
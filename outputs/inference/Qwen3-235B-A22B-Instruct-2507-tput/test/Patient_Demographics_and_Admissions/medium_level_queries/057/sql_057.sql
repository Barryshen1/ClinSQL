WITH icu_ages AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.los,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM i.intime) AS intime_year,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
),
filtered AS (
  SELECT
    stay_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_group
  FROM icu_ages
  WHERE gender = 'F'
    AND age_at_icu_admission >= 40
    AND age_at_icu_admission <= 50
    AND los IS NOT NULL
),
grouped AS (
  SELECT
    discharge_group,
    los,
    CASE WHEN los <= 7 THEN 1 ELSE 0 END AS los_le_7
  FROM filtered
  WHERE discharge_group IN ('Home', 'Hospice', 'In-hospital death')
)
SELECT
  discharge_group,
  ROUND(PERCENTILE_CONT(los, 0.50) OVER (PARTITION BY discharge_group), 2) AS p50_los,
  ROUND(PERCENTILE_CONT(los, 0.75) OVER (PARTITION BY discharge_group), 2) AS p75_los,
  ROUND(PERCENTILE_CONT(los, 0.90) OVER (PARTITION BY discharge_group), 2) AS p90_los,
  ROUND(PERCENTILE_CONT(los, 0.95) OVER (PARTITION BY discharge_group), 2) AS p95_los,
  ROUND(AVG(los_le_7) * 100, 2) AS pct_los_le_7
FROM grouped
GROUP BY discharge_group, los, los_le_7
ORDER BY discharge_group;
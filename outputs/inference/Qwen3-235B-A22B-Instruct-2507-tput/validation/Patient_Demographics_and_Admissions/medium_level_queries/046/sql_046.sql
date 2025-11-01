WITH icu_ages AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_icu_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
),
filtered AS (
  SELECT
    stay_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'home'
      ELSE 'facility'
    END AS outcome_group
  FROM icu_ages
  WHERE gender = 'F'
    AND age_at_icu_admit BETWEEN 87 AND 97
    AND los IS NOT NULL
),
summary AS (
  SELECT
    outcome_group,
    COUNT(*) AS n,
    AVG(los) AS mean_los,
    STDDEV(los) AS sd_los,
    AVG(CASE WHEN los < 10 THEN 1.0 ELSE 0.0 END) AS pct_los_lt_10
  FROM filtered
  GROUP BY outcome_group
)
SELECT
  outcome_group,
  n,
  ROUND(mean_los, 2) || '±' || ROUND(sd_los, 2) AS mean_sd_los,
  ROUND(100 * pct_los_lt_10, 1) AS pct_los_lt_10
FROM summary
ORDER BY outcome_group;
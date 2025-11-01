WITH base AS (
  SELECT
    a.hadm_id,
    icu.los AS los_icu,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE NULL
    END AS outcome_label
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND icu.los IS NOT NULL
    AND (
      a.hospital_expire_flag = 1
      OR LOWER(a.discharge_location) LIKE '%home%'
      OR LOWER(a.discharge_location) LIKE '%hospice%'
    )
)

SELECT
  outcome_label,
  PERCENTILE_CONT(los_icu, 0.50) OVER (PARTITION BY outcome_label) AS p50,
  PERCENTILE_CONT(los_icu, 0.75) OVER (PARTITION BY outcome_label) AS p75,
  PERCENTILE_CONT(los_icu, 0.90) OVER (PARTITION BY outcome_label) AS p90,
  PERCENTILE_CONT(los_icu, 0.95) OVER (PARTITION BY outcome_label) AS p95,
  100.0 * SUM(CASE WHEN los_icu <= 7 THEN 1 ELSE 0 END) OVER (PARTITION BY outcome_label)
    / COUNT(*) OVER (PARTITION BY outcome_label) AS pct_le7,
  COUNT(*) OVER (PARTITION BY outcome_label) AS n
FROM base
WHERE outcome_label IS NOT NULL
ORDER BY outcome_label;
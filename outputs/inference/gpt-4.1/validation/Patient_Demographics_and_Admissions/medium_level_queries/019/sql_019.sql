WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND (
      LOWER(a.admission_location) LIKE '%transfer%'
      OR LOWER(a.admission_location) LIKE '%hospital%'
    )
)
, categorized AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    discharge_location,
    -- Categorize outcome
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS outcome,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    cohort
)
SELECT
  outcome,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days
FROM
  categorized
WHERE
  outcome IS NOT NULL
GROUP BY
  outcome
ORDER BY
  outcome;
WITH filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(a.admission_type) LIKE '%transfer%'
    -- Female patients only
    AND LOWER(p.gender) = 'f'
    -- Age at admission between 63 and 73 years
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
    -- Ensure we have an end time
    AND a.dischtime IS NOT NULL
),
labeled AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.deathtime,
    s.discharge_location,
    s.hospital_expire_flag,
    -- Length of stay in days (fractional)
    TIMESTAMP_DIFF(TIMESTAMP(s.dischtime), TIMESTAMP(s.admittime), SECOND) / 86400.0 AS los_days,
    -- Stratify discharge disposition
    CASE
      WHEN s.hospital_expire_flag = 1 OR s.deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN LOWER(s.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(s.discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS strat
  FROM filtered s
)
SELECT
  strat AS discharge_group,
  AVG(los_days) AS mean_los_days,
  STDDEV_SAMP(los_days) AS sd_los_days
FROM labeled
WHERE strat IS NOT NULL
GROUP BY strat
ORDER BY strat;
WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND UPPER(a.admission_location) LIKE 'TRANSFER%'
),
labeled AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN hospital_expire_flag = 0
           AND UPPER(discharge_location) LIKE 'HOME%' THEN 'Discharged home'
      WHEN hospital_expire_flag = 0 THEN 'Discharged to facility'
      ELSE 'Other'
    END AS outcome
  FROM cohort
  WHERE
    -- Exclude anything not in our three desired outcome categories
    (hospital_expire_flag = 1)
    OR (hospital_expire_flag = 0 AND UPPER(discharge_location) LIKE 'HOME%')
    OR (hospital_expire_flag = 0 AND NOT UPPER(discharge_location) LIKE 'HOME%')
)
SELECT
  outcome,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_POP(los_days), 2) AS sd_los_days,
  ROUND(
    100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS pct_rank_5day
FROM
  labeled
GROUP BY
  outcome
ORDER BY
  -- Order results in a logical order
  CASE outcome
    WHEN 'Discharged home' THEN 1
    WHEN 'Discharged to facility' THEN 2
    WHEN 'In-hospital death' THEN 3
    ELSE 4
  END;
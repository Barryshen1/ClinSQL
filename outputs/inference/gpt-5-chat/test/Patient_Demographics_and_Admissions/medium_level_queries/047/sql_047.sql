WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- precise LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_group,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days,
  ROUND(100 * COUNTIF(los_days <= 5) / COUNT(*), 2) AS percentile_rank_5day
FROM (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group
  FROM cohort
)
GROUP BY discharge_group
ORDER BY discharge_group;
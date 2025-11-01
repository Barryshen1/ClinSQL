WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    s.curr_service,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN (
    SELECT subject_id, hadm_id, curr_service
    FROM (
      SELECT
        subject_id,
        hadm_id,
        curr_service,
        transfertime,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY transfertime) AS rn
      FROM `physionet-data.mimiciv_3_1_hosp.services`
    )
    WHERE rn = 1
  ) s
    ON a.subject_id = s.subject_id
    AND a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND s.curr_service LIKE 'MED%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
-- proportions by mortality status
, proportions AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS total_patients,
    COUNTIF(los_days >= 7) AS los_ge_7_count,
    SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS proportion_los_ge_7
  FROM cohort
  GROUP BY hospital_expire_flag
)
-- percentile rank of 7-day LOS in this cohort
, percentile_7d AS (
  SELECT
    SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_rank_7d
  FROM cohort
)
SELECT
  p.hospital_expire_flag,
  p.total_patients,
  p.los_ge_7_count,
  p.proportion_los_ge_7,
  pr.percentile_rank_7d
FROM proportions p
CROSS JOIN percentile_7d pr
ORDER BY p.hospital_expire_flag;
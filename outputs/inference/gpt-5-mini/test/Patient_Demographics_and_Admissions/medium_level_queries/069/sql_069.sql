WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND UPPER(a.admission_type) = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND UPPER(COALESCE(s.curr_service, '')) LIKE '%MED%'
    )
)

SELECT
  CASE WHEN hospital_expire_flag = 1 THEN 'In-hospital death' ELSE 'Discharged alive' END AS outcome,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_los_ge_7,
  ROUND(100.0 * SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_ge_7,
  /* Percentile rank of a 7-day LOS defined as proportion with LOS <= 7 days (in percent) */
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_rank_7day
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag DESC;
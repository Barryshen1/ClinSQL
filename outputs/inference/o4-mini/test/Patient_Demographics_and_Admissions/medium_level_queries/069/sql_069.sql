WITH filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    -- ensure we only count true hospital stays
    AND a.dischtime IS NOT NULL
),
stats AS (
  SELECT
    COUNT(*) AS total_n,
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) AS n_le_7
  FROM filtered
),
by_flag AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS count_n,
    COUNTIF(los_days >= 7) AS n_ge_7
  FROM filtered
  GROUP BY hospital_expire_flag
)
SELECT
  bf.hospital_expire_flag,
  bf.count_n AS patient_count,
  SAFE_DIVIDE(bf.n_ge_7, s.total_n) AS proportion_los_ge_7,
  SAFE_DIVIDE(s.n_le_7, s.total_n) AS percentile_rank_7_day_los
FROM
  by_flag bf
  CROSS JOIN stats s
ORDER BY
  bf.hospital_expire_flag;
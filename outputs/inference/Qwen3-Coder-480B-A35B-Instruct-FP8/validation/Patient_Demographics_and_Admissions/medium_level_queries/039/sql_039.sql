WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'DIED'
      ELSE a.discharge_location
    END AS discharge_outcome
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type IN ('URGENT', 'EMERGENCY')
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND (
      a.discharge_location IN ('HOME', 'FACILITY')
      OR a.hospital_expire_flag = 1
    )
),

los_stats AS (
  SELECT
    discharge_outcome,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_p25,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_p50,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_p75,
    COUNT(*) AS total_stays,
    SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) AS stays_le_7_days
  FROM
    filtered_admissions
  GROUP BY
    discharge_outcome
)

SELECT
  discharge_outcome,
  mean_los,
  los_p25,
  los_p50,
  los_p75,
  ROUND(SAFE_DIVIDE(stays_le_7_days, total_stays), 4) AS percentile_rank_7_day
FROM
  los_stats
ORDER BY
  discharge_outcome;
WITH candidate_inpatients AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS mortality_flag,
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE UPPER(p.gender) = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    -- PE diagnosis (ICD-10 I26*, ICD-9 415*)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
          OR (di.icd_version = 9  AND di.icd_code LIKE '415%')
        )
    )
),

lis_all AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.mortality_flag,
    c.los_days,
    -- 72-hour lab instability score: count of abnormal labs within 72h
    SUM(
      CASE
        WHEN le.valuenum IS NOT NULL
             AND (
                   (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                   OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
                 )
        THEN 1
        ELSE 0
      END
    ) AS lis,
    -- 72-hour critical-lab indicator (any_CRITICAL within 72h)
    MAX(CASE WHEN LOWER(le.flag) LIKE '%critical%' THEN 1 ELSE 0 END) AS any_critical_lab
  FROM candidate_inpatients AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON c.hadm_id = le.hadm_id
   AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.mortality_flag,
    c.los_days
),

threshold AS (
  -- 75th percentile of LIS across admissions (rounded to int)
  SELECT CAST(APPROX_QUANTILES(lis, 100)[OFFSET(75)] AS INT64) AS lis_75
  FROM lis_all
),

joined AS (
  SELECT
    la.*,
    t.lis_75
  FROM lis_all AS la
  CROSS JOIN threshold AS t
),

metrics AS (
  SELECT
    lis_75,
    -- Mortality rate in threshold group
    AVG(CASE WHEN lis >= lis_75 THEN mortality_flag END) AS mortality_rate_threshold,
    -- Mean LOS in threshold group
    AVG(CASE WHEN lis >= lis_75 THEN los_days END) AS mean_los_threshold,
    -- Critical-lab rate in threshold group
    AVG(CASE WHEN lis >= lis_75 THEN any_critical_lab END) AS critical_rate_threshold,
    -- Critical-lab rate in overall inpatients (across all admissions in cohort)
    AVG(any_critical_lab) AS critical_rate_overall
  FROM joined
  GROUP BY lis_75
)

SELECT
  lis_75 AS threshold_75th_percentile,
  mortality_rate_threshold * 100 AS mortality_percent_threshold,
  mean_los_threshold,
  critical_rate_threshold * 100 AS critical_lab_rate_threshold,
  critical_rate_overall * 100 AS critical_lab_rate_overall
FROM metrics
ORDER BY threshold_75th_percentile
LIMIT 1;
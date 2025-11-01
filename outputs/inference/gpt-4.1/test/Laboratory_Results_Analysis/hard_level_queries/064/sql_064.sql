WITH pancreatitis_dx AS (
  -- Identify admissions with acute pancreatitis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND (
      -- ICD-10 K85.x or ICD-9 577.0
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^K85'))
      OR (d.icd_version = 9 AND d.icd_code = '5770')
    )
),

age_matched_inpatients AS (
  -- All female inpatients aged 65-75
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),

lab_instability AS (
  -- Calculate instability score and critical lab flag for each admission
  SELECT
    l.hadm_id,
    COUNTIF(
      SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
      AND (
        SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64)
        OR SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64)
      )
    ) AS instability_score,
    COUNTIF(
      SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
      AND (
        SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64) * 0.5
        OR SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64) * 2
      )
    ) > 0 AS has_critical_lab
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN pancreatitis_dx a
      ON l.hadm_id = a.hadm_id
  WHERE
    l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    l.hadm_id
),

pancreatitis_cohort AS (
  -- Combine pancreatitis admissions with their instability scores
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los,
    COALESCE(l.instability_score, 0) AS instability_score,
    COALESCE(l.has_critical_lab, FALSE) AS has_critical_lab
  FROM
    pancreatitis_dx a
    LEFT JOIN lab_instability l
      ON a.hadm_id = l.hadm_id
),

-- Calculate quintiles for instability score
quintiles AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.2) OVER() AS q1,
    PERCENTILE_CONT(instability_score, 0.4) OVER() AS q2,
    PERCENTILE_CONT(instability_score, 0.6) OVER() AS q3,
    PERCENTILE_CONT(instability_score, 0.8) OVER() AS q4
  FROM pancreatitis_cohort
  LIMIT 1
),

pancreatitis_quintiled AS (
  SELECT
    *,
    CASE
      WHEN instability_score <= q.q1 THEN 1
      WHEN instability_score <= q.q2 THEN 2
      WHEN instability_score <= q.q3 THEN 3
      WHEN instability_score <= q.q4 THEN 4
      ELSE 5
    END AS quintile
  FROM
    pancreatitis_cohort c
    CROSS JOIN quintiles q
),

-- Age-matched inpatients: instability and critical labs
lab_instability_all AS (
  SELECT
    l.hadm_id,
    COUNTIF(
      SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
      AND (
        SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64)
        OR SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64)
      )
    ) AS instability_score,
    COUNTIF(
      SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
      AND (
        SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64) * 0.5
        OR SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64) * 2
      )
    ) > 0 AS has_critical_lab
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN age_matched_inpatients a
      ON l.hadm_id = a.hadm_id
  WHERE
    l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    l.hadm_id
),

age_matched_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los,
    COALESCE(l.instability_score, 0) AS instability_score,
    COALESCE(l.has_critical_lab, FALSE) AS has_critical_lab
  FROM
    age_matched_inpatients a
    LEFT JOIN lab_instability_all l
      ON a.hadm_id = l.hadm_id
)

-- Final output: stats per quintile for pancreatitis, and stats for age-matched inpatients
SELECT
  'pancreatitis_quintile' AS group_type,
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(instability_score),2) AS mean_instability,
  ROUND(AVG(los),2) AS mean_los,
  ROUND(AVG(hospital_expire_flag)*100,2) AS mortality_percent,
  ROUND(AVG(CASE WHEN has_critical_lab THEN 1 ELSE 0 END)*100,2) AS percent_with_critical_lab
FROM pancreatitis_quintiled
GROUP BY quintile

UNION ALL

SELECT
  'age_matched_inpatients' AS group_type,
  NULL AS quintile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(instability_score),2) AS mean_instability,
  ROUND(AVG(los),2) AS mean_los,
  ROUND(AVG(hospital_expire_flag)*100,2) AS mortality_percent,
  ROUND(AVG(CASE WHEN has_critical_lab THEN 1 ELSE 0 END)*100,2) AS percent_with_critical_lab
FROM age_matched_cohort;
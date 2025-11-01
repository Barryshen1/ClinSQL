WITH cohort_adms AS (
  -- male inpatients age 35-45 with an acute pancreatitis diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 35 AND 45
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(COALESCE(dd.long_title, '')) LIKE '%acute pancreatitis%'
    )
),

diag_flags AS (
  -- diagnosis counts and complication flags for each admission in the cohort
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS diagnosis_count,
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%respiratory failure%' THEN 1 ELSE 0 END) AS resp_fail_flag,
    MAX(CASE WHEN (
           LOWER(COALESCE(dd.long_title, '')) LIKE '%acute kidney%'
        OR LOWER(COALESCE(dd.long_title, '')) LIKE '%acute renal failure%'
        OR LOWER(COALESCE(dd.long_title, '')) LIKE '%acute renal %'
      ) THEN 1 ELSE 0 END) AS aki_flag,
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%sepsis%'
           OR LOWER(COALESCE(dd.long_title, '')) LIKE '%septicemia%'
           OR LOWER(COALESCE(dd.long_title, '')) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS sepsis_flag,
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%shock%' THEN 1 ELSE 0 END) AS shock_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM cohort_adms)
  GROUP BY d.hadm_id
),

admission_scores AS (
  -- combine admissions with diagnosis-derived metrics, compute risk score and LOS
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(df.diagnosis_count, 0) AS diagnosis_count,
    COALESCE(df.resp_fail_flag, 0) AS resp_fail_flag,
    COALESCE(df.aki_flag, 0) AS aki_flag,
    COALESCE(df.sepsis_flag, 0) AS sepsis_flag,
    COALESCE(df.shock_flag, 0) AS shock_flag,
    (COALESCE(df.resp_fail_flag, 0)
     + COALESCE(df.aki_flag, 0)
     + COALESCE(df.sepsis_flag, 0)
     + COALESCE(df.shock_flag, 0)
    ) AS num_major_complications,
    (COALESCE(df.diagnosis_count, 0)
     + 5 * (COALESCE(df.resp_fail_flag, 0)
            + COALESCE(df.aki_flag, 0)
            + COALESCE(df.sepsis_flag, 0)
            + COALESCE(df.shock_flag, 0)
           )
    ) AS risk_score,
    -- LOS in days as a floating point number
    SAFE_DIVIDE(TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND), 86400.0) AS los_days
  FROM cohort_adms c
  LEFT JOIN diag_flags df
    ON c.hadm_id = df.hadm_id
),

scored_ntile AS (
  -- assign quartiles (NTILE(4)) by risk_score
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score ASC) AS risk_quartile
  FROM admission_scores
),

agg_by_quartile AS (
  -- aggregate metrics per quartile
  SELECT
    CONCAT('Q', CAST(risk_quartile AS STRING)) AS quartile,
    COUNT(*) AS n_admissions,
    ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 2) AS inhospital_mortality_pct,
    ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN num_major_complications > 0 THEN 1 ELSE 0 END), COUNT(*)), 2) AS major_complication_rate_pct,
    -- approximate median LOS among survivors using APPROX_QUANTILES; return NULL if no survivors
    (CASE
       WHEN SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END) = 0 THEN NULL
       ELSE (APPROX_QUANTILES(
               CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END,
               100
             )[OFFSET(50)])
     END) AS median_survivor_los_days
  FROM scored_ntile
  GROUP BY risk_quartile
  ORDER BY risk_quartile
),

agg_overall AS (
  -- overall metrics for the cohort
  SELECT
    'Overall' AS quartile,
    COUNT(*) AS n_admissions,
    ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 2) AS inhospital_mortality_pct,
    ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN num_major_complications > 0 THEN 1 ELSE 0 END), COUNT(*)), 2) AS major_complication_rate_pct,
    (CASE
       WHEN SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END) = 0 THEN NULL
       ELSE (APPROX_QUANTILES(
               CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END,
               100
             )[OFFSET(50)])
     END) AS median_survivor_los_days
  FROM scored_ntile
)

-- final output: quartiles followed by overall
SELECT * FROM agg_by_quartile
UNION ALL
SELECT * FROM agg_overall
ORDER BY
  CASE WHEN quartile = 'Q1' THEN 1
       WHEN quartile = 'Q2' THEN 2
       WHEN quartile = 'Q3' THEN 3
       WHEN quartile = 'Q4' THEN 4
       ELSE 5 END;
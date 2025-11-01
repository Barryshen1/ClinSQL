WITH eligible_admissions AS (
  -- All hospital admissions of female patients aged 84–94
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

echocardiography_counts AS (
  -- Count distinct echocardiography ICD procedures per admission
  SELECT
    pi.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS echo_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pi.icd_code = dp.icd_code
     AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%echocardi%'
  GROUP BY
    pi.hadm_id
),

hadm_with_counts AS (
  -- Combine all eligible admissions with their echo counts (zero if none)
  SELECT
    ea.hadm_id,
    COALESCE(ec.echo_count, 0) AS echo_count
  FROM
    eligible_admissions ea
    LEFT JOIN echocardiography_counts ec
      ON ea.hadm_id = ec.hadm_id
)

-- Compute the 25th percentile of distinct echo procedures per admission
SELECT
  -- APPROX_QUANTILES returns an array of n+1 quantile boundaries for n
  -- APPROX_QUANTILES(..., 100)[OFFSET(25)] approximates the 25th percentile
  APPROX_QUANTILES(echo_count, 100)[OFFSET(25)] AS echo_count_25th_percentile
FROM
  hadm_with_counts;
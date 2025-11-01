WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'E11%'  -- Type 2 diabetes
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50%'  -- Heart failure
    )
),
glp1_exposures AS (
  SELECT
    c.hadm_id,
    MAX(CASE
          WHEN pr.starttime BETWEEN c.admittime
                               AND TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
          THEN 1 ELSE 0
        END) AS first24_flag,
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 2 DAY)
                               AND c.dischtime
          THEN 1 ELSE 0
        END) AS last48_flag
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.hadm_id = c.hadm_id
  WHERE
    -- Filter to injectable GLP-1 analogues
    LOWER(pr.drug) LIKE '%tide%'
    AND (
      LOWER(pr.route) LIKE '%subcut%' 
      OR LOWER(pr.route) LIKE '%sc%'
    )
  GROUP BY
    c.hadm_id
),
metrics AS (
  SELECT
    COUNT(*) AS cohort_n,
    SUM(first24_flag) AS n_first24,
    SUM(last48_flag) AS n_last48
  FROM
    glp1_exposures
)
SELECT
  cohort_n,
  n_first24,
  ROUND(100.0 * n_first24 / cohort_n, 2) AS pct_first24,
  n_last48,
  ROUND(100.0 * n_last48 / cohort_n, 2) AS pct_last48,
  ROUND(100.0 * (n_last48 - n_first24) / cohort_n, 2) AS abs_change_pct,
  CASE
    WHEN n_first24 = 0 THEN NULL
    ELSE ROUND(( (n_last48 - n_first24) / n_first24 ) * 100.0, 2)
  END AS rel_change_pct
FROM
  metrics;
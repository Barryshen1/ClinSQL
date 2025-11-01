WITH cohort AS (
  -- 1. Identify male age 36-46 inpatients with both diabetes and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.hadm_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      WHERE dx.hadm_id = a.hadm_id
        AND (
          (dx.icd_version = 9 AND STARTS_WITH(dx.icd_code, '250'))
          OR (dx.icd_version = 10 AND STARTS_WITH(dx.icd_code, 'E11'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      WHERE dx.hadm_id = a.hadm_id
        AND (
          (dx.icd_version = 9 AND STARTS_WITH(dx.icd_code, '428'))
          OR (dx.icd_version = 10 AND STARTS_WITH(dx.icd_code, 'I50'))
        )
    )
),
cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_admissions
  FROM cohort
),
drug_exposures AS (
  -- 2. Extract and classify prescriptions in the two windows
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Antidiabetic'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Antidiabetic'
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 'Antidiabetic'
      WHEN LOWER(p.drug) LIKE '%lisinopril%' THEN 'Cardiac'
      WHEN LOWER(p.drug) LIKE '%metoprolol%' THEN 'Cardiac'
      WHEN LOWER(p.drug) LIKE '%furosemide%' THEN 'Cardiac'
      ELSE NULL
    END AS drug_class,
    CASE
      WHEN p.starttime BETWEEN c.admittime
            AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
        THEN 'first_48h'
      WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
            AND c.dischtime
        THEN 'last_12h'
      ELSE NULL
    END AS time_window
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
      ON c.hadm_id = p.hadm_id
),
filtered_exposures AS (
  -- 2b. Keep only the relevant exposures
  SELECT
    hadm_id,
    drug_class,
    time_window
  FROM
    drug_exposures
  WHERE
    drug_class IS NOT NULL
    AND time_window IS NOT NULL
),
agg AS (
  -- 3. Count distinct admissions by drug class and window
  SELECT
    drug_class,
    time_window,
    COUNT(DISTINCT hadm_id) AS admissions_with_drug
  FROM
    filtered_exposures
  GROUP BY
    drug_class,
    time_window
),
results AS (
  -- 4. Compute prevalence (%) and differences
  SELECT
    d.drug_class,
    SAFE_DIVIDE(COALESCE(a1.admissions_with_drug, 0), cs.n_admissions) * 100 AS pct_first_48h,
    SAFE_DIVIDE(COALESCE(a2.admissions_with_drug, 0), cs.n_admissions) * 100 AS pct_last_12h,
    (
      SAFE_DIVIDE(COALESCE(a2.admissions_with_drug, 0), cs.n_admissions)
      - SAFE_DIVIDE(COALESCE(a1.admissions_with_drug, 0), cs.n_admissions)
    ) * 100 AS abs_diff_pct_points
  FROM
    (SELECT DISTINCT drug_class FROM agg) AS d
    CROSS JOIN cohort_size AS cs
    LEFT JOIN agg AS a1
      ON a1.drug_class = d.drug_class
     AND a1.time_window = 'first_48h'
    LEFT JOIN agg AS a2
      ON a2.drug_class = d.drug_class
     AND a2.time_window = 'last_12h'
)
SELECT
  drug_class,
  ROUND(pct_first_48h, 1)       AS pct_first_48h,
  ROUND(pct_last_12h, 1)        AS pct_last_12h,
  ROUND(abs_diff_pct_points, 1) AS abs_diff_pct_points
FROM
  results
ORDER BY
  drug_class;
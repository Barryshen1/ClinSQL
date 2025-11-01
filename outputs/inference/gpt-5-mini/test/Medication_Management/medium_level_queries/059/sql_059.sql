WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70

    -- Must have a diagnosis of T2DM on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'E11'))  -- ICD-10 type 2 DM
          OR
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250')) -- ICD-9 250.*
        )
    )

    -- Must have a diagnosis of Heart Failure on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))  -- ICD-10 heart failure
          OR
          (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '428'))   -- ICD-9 heart failure
        )
    )
),

-- All prescriptions during the admission window, with normalized drug lowercase
presc_in_adm AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    LOWER(COALESCE(p.drug, '')) AS drug_text
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE
    p.starttime IS NOT NULL
    AND p.starttime BETWEEN c.admittime AND c.dischtime
),

-- Assign each prescription to a class (if matches). Keep only prescriptions that match one of the classes.
presc_with_class AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    starttime,
    CASE
      WHEN drug_text LIKE '%insulin%' 
           OR drug_text LIKE '%metformin%' 
           OR drug_text LIKE '%sitagliptin%' 
           OR drug_text LIKE '%saxagliptin%' 
           OR drug_text LIKE '%alogliptin%' 
           OR drug_text LIKE '%linagliptin%'
           OR drug_text LIKE '%empagliflozin%'
           OR drug_text LIKE '%canagliflozin%'
           OR drug_text LIKE '%dapagliflozin%'
           OR drug_text LIKE '%glipizide%'
           OR drug_text LIKE '%glyburide%'
           OR drug_text LIKE '%glimepiride%'
           OR drug_text LIKE '%pioglitazone%'
           OR drug_text LIKE '%liraglutide%'
           OR drug_text LIKE '%semaglutide%'
      THEN 'antidiabetics'

      WHEN drug_text LIKE '%metoprolol%'
           OR drug_text LIKE '%atenolol%'
           OR drug_text LIKE '%propranolol%'
           OR drug_text LIKE '%carvedilol%'
           OR drug_text LIKE '%bisoprolol%'
           OR drug_text LIKE '%labetalol%'
           OR drug_text LIKE '%nadolol%'
           OR drug_text LIKE '%nebivolol%'
      THEN 'beta_blockers'

      WHEN drug_text LIKE '%lisinopril%'
           OR drug_text LIKE '%enalapril%'
           OR drug_text LIKE '%ramipril%'
           OR drug_text LIKE '%benazepril%'
           OR drug_text LIKE '%captopril%'
           OR drug_text LIKE '%trandolapril%'
           OR drug_text LIKE '%losartan%'
           OR drug_text LIKE '%valsartan%'
           OR drug_text LIKE '%irbesartan%'
           OR drug_text LIKE '%candesartan%'
           OR drug_text LIKE '%sacubitril%'
           OR drug_text LIKE '%entresto%'
      THEN 'acei_arp_arni'

      WHEN drug_text LIKE '%furosemide%'
           OR drug_text LIKE '%bumetanide%'
           OR drug_text LIKE '%torsemide%'
      THEN 'loop_diuretics'

      ELSE NULL
    END AS drug_class
  FROM presc_in_adm
  WHERE drug_text IS NOT NULL
),

-- For each hadm_id and drug_class, find earliest (first) starttime during the admission
first_start_by_class AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    drug_class,
    MIN(starttime) AS first_starttime
  FROM presc_with_class
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, admittime, dischtime, drug_class
),

-- Cohort size
cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS N
  FROM cohort
)

-- Final aggregation: for each class compute counts and percentages
SELECT
  fc.drug_class AS drug_class,
  cs.N AS cohort_n,
  COUNTIF(fc.first_starttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)) AS initiated_first48_n,
  ROUND(100.0 * COUNTIF(fc.first_starttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)) / cs.N, 2) AS initiated_first48_pct,
  COUNTIF(
    fc.first_starttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 24 HOUR)
    AND fc.first_starttime <= fc.dischtime
  ) AS initiated_final24_n,
  ROUND(
    100.0 * COUNTIF(
      fc.first_starttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 24 HOUR)
      AND fc.first_starttime <= fc.dischtime
    ) / cs.N, 2
  ) AS initiated_final24_pct,
  ROUND(
    100.0 * COUNTIF(fc.first_starttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)) / cs.N
    -
    100.0 * COUNTIF(
      fc.first_starttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 24 HOUR)
      AND fc.first_starttime <= fc.dischtime
    ) / cs.N
  , 2) AS absolute_difference_pct_points
FROM
  first_start_by_class fc
  CROSS JOIN cohort_size cs
GROUP BY
  fc.drug_class,
  cs.N
ORDER BY
  drug_class;
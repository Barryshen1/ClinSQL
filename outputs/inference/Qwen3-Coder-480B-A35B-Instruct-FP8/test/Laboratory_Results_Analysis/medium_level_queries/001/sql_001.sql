WITH ami_admissions AS (
  -- Get admissions with primary AMI diagnosis
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),

filtered_patients AS (
  -- Filter for female patients aged 40–50
  SELECT
    subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

troponin_first AS (
  -- Get first Troponin T value per admission
  SELECT
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON l.hadm_id = a.hadm_id
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN a.admittime AND a.dischtime
),

troponin_initial_values AS (
  -- Select only the first (earliest) Troponin T value per admission
  SELECT
    hadm_id,
    valuenum
  FROM
    troponin_first
  WHERE
    rn = 1
),

categorized_values AS (
  -- Categorize Troponin T values
  SELECT
    hadm_id,
    CASE
      WHEN valuenum <= 0.01 THEN 'Normal'
      WHEN valuenum > 0.01 AND valuenum <= 0.04 THEN 'Borderline'
      WHEN valuenum > 0.04 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM
    troponin_initial_values
)

-- Final count by category
SELECT
  troponin_category,
  COUNT(*) AS count
FROM
  categorized_values
JOIN
  ami_admissions aa
  ON categorized_values.hadm_id = aa.hadm_id
JOIN
  filtered_patients fp
  ON aa.subject_id = fp.subject_id
GROUP BY
  troponin_category
ORDER BY
  troponin_category;
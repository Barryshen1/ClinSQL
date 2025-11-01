WITH cohort AS (
  -- Step 1: Select male patients aged 41-51 admitted with chest pain or AMI
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND (
      -- Chest pain ICD codes (ICD-10: R07.9, R07.2; ICD-9: 786.50, 786.51, etc.)
      (LOWER(dd.long_title) LIKE '%chest pain%')
      OR
      -- AMI ICD codes (ICD-10: I21, I22; ICD-9: 410)
      (LOWER(dd.long_title) LIKE '%myocardial infarction%' OR LOWER(dd.long_title) LIKE '%ami%')
    )
),
troponin_t_items AS (
  -- Step 2: Find Troponin T itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin AS (
  -- Step 3: Get initial Troponin T value per patient/admission
  SELECT
    c.subject_id,
    c.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
    INNER JOIN troponin_t_items tti
      ON l.itemid = tti.itemid
  WHERE
    l.valuenum IS NOT NULL
),
first_troponin AS (
  -- Step 4: Select the first Troponin T per patient/admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
  FROM initial_troponin
),
categorized_troponin AS (
  -- Step 5: Assign category to initial troponin
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum <= 0.01 THEN 'Normal'
      WHEN valuenum > 0.01 AND valuenum <= 0.03 THEN 'Borderline'
      WHEN valuenum > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM first_troponin
  WHERE rn = 1
)
SELECT
  troponin_category,
  COUNT(*) AS n_patients,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_patients,
  ROUND(AVG(valuenum), 4) AS mean_troponin,
  ROUND(APPROX_QUANTILES(valuenum, 3)[OFFSET(1)], 4) AS median_troponin,
  ROUND(APPROX_QUANTILES(valuenum, 3)[OFFSET(0)], 4) AS troponin_25th,
  ROUND(APPROX_QUANTILES(valuenum, 3)[OFFSET(2)], 4) AS troponin_75th,
  ROUND(APPROX_QUANTILES(valuenum, 3)[OFFSET(2)] - APPROX_QUANTILES(valuenum, 3)[OFFSET(0)], 4) AS troponin_iqr
FROM
  categorized_troponin
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;
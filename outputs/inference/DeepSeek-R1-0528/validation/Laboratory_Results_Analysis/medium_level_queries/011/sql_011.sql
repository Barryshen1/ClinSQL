WITH cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 61 AND 71
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'R07%') 
      OR (diag.icd_version = 9 AND diag.icd_code = '7865')
    )
    AND diag.seq_num = 1  -- Primary diagnosis
),
initial_troponin AS (
  SELECT
    lab.hadm_id,
    lab.valuenum,
    lab.valueuom,
    COALESCE(lab.ref_range_upper, 14) AS ref_upper,  -- Default upper limit: 14 ng/L
    ROW_NUMBER() OVER (
      PARTITION BY lab.hadm_id
      ORDER BY lab.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN cohort c
    ON lab.hadm_id = c.hadm_id
  WHERE
    lab.itemid = 51003  -- hs-TnT
    AND lab.valuenum IS NOT NULL
    AND lab.valueuom = 'ng/L'  -- Ensure correct unit
),
categorized_troponin AS (
  SELECT
    hadm_id,
    CASE
      WHEN valuenum <= ref_upper THEN 'Normal'
      WHEN valuenum <= 52 THEN 'Borderline'  -- Clinical cutoff for borderline
      ELSE 'Myocardial injury'               -- >52 ng/L indicates injury
    END AS category
  FROM initial_troponin
  WHERE rn = 1  -- First result per admission
)
SELECT
  category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized_troponin
GROUP BY category
ORDER BY category;
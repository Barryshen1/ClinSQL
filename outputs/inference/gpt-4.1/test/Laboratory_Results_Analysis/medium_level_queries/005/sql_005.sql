WITH cohort AS (
  -- Step 1: Male patients aged 35-45
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
),
dx_chestpain_ami AS (
  -- Step 2: Admissions with chest pain or AMI
  SELECT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON c.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  WHERE
    (
      -- Chest pain ICD codes (ICD-10: R07.9, ICD-9: 786.50, etc.)
      (dx.icd_version = 10 AND dx.icd_code LIKE 'R07%')
      OR (dx.icd_version = 9 AND dx.icd_code LIKE '7865%')
      -- AMI ICD codes (ICD-10: I21.x, ICD-9: 410.x)
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I21%')
      OR (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
    )
),
troponin_items AS (
  -- Step 3: Find itemid for high-sensitivity troponin T
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%sens%' -- "high sensitivity"
),
first_tnt AS (
  -- Step 4: First hs-TnT per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN dx_chestpain_ami dx
      ON l.subject_id = dx.subject_id AND l.hadm_id = dx.hadm_id
    JOIN troponin_items ti
      ON l.itemid = ti.itemid
  WHERE
    l.valuenum IS NOT NULL
),
first_tnt_per_admission AS (
  -- Step 5: Only first hs-TnT per admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    valueuom,
    itemid
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM
      first_tnt
  )
  WHERE rn = 1
),
categorized AS (
  -- Step 6: Categorize hs-TnT value
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    valueuom,
    CASE
      -- Assume valueuom is ng/L; if not, adjust accordingly
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum >= 14 AND valuenum <= 52 THEN 'Borderline'
      WHEN valuenum > 52 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS tnt_category
  FROM
    first_tnt_per_admission
  WHERE
    valueuom = 'ng/L' -- Only include ng/L for simplicity
)
SELECT
  tnt_category,
  COUNT(*) AS admission_count
FROM
  categorized
GROUP BY
  tnt_category
ORDER BY
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial injury' THEN 3
    ELSE 4
  END;
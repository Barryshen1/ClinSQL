WITH ami_admissions AS (
  -- Identify male patients age 77-87 with AMI
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND (
      -- ICD-10 AMI: I21.x, I22.x; ICD-9 AMI: 410.x
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
      OR
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
    )
    AND diag.seq_num = 1 -- primary diagnosis
),

hs_tnt_items AS (
  -- Find itemids for hs-TnT
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%high%'
),

initial_hs_tnt AS (
  -- For each AMI admission, get the earliest hs-TnT measurement
  SELECT
    a.subject_id,
    a.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM
    ami_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
    JOIN hs_tnt_items h
      ON l.itemid = h.itemid
  WHERE
    l.valuenum IS NOT NULL
),
first_hs_tnt AS (
  -- Get the first hs-TnT per admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    valueuom
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC, valuenum ASC) AS rn
    FROM initial_hs_tnt
  )
  WHERE rn = 1
),

categorized AS (
  -- Categorize hs-TnT values
  SELECT
    hadm_id,
    subject_id,
    valuenum,
    valueuom,
    CASE
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum >= 14 AND valuenum <= 52 THEN 'Borderline'
      WHEN valuenum > 52 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS hs_tnt_category
  FROM first_hs_tnt
  WHERE valueuom = 'ng/L' -- restrict to ng/L for consistency
)

SELECT
  hs_tnt_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percent_of_total
FROM categorized
WHERE hs_tnt_category != 'Unknown'
GROUP BY hs_tnt_category
ORDER BY hs_tnt_category;
WITH chest_pain_ami_admissions AS (
  -- Get admissions for males age 50-60 with chest pain or AMI
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      -- Chest pain ICD codes
      (d.icd_version = 9 AND d.icd_code IN ('78650','78651','78652','78659'))
      OR (d.icd_version = 10 AND d.icd_code IN ('R079','R072','R071','R0789'))
      -- AMI ICD codes
      OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),

hs_tnt_itemids AS (
  -- Get itemid for hs-TnT
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin%' AND LOWER(label) LIKE '%high sensitivity%'
),

initial_hs_tnt AS (
  -- For each admission, get the first hs-TnT value
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
    JOIN hs_tnt_itemids tnt ON l.itemid = tnt.itemid
    JOIN chest_pain_ami_admissions cpa ON l.subject_id = cpa.subject_id AND l.hadm_id = cpa.hadm_id
  WHERE
    l.valuenum IS NOT NULL
),
first_hs_tnt_per_admission AS (
  -- Get the earliest hs-TnT per admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum AS initial_hs_tnt
  FROM (
    SELECT
      subject_id,
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM initial_hs_tnt
  )
  WHERE rn = 1
    AND valuenum > 0.014 -- ULN
)

SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(AVG(initial_hs_tnt), 4) AS mean_initial_hs_tnt,
  ROUND(APPROX_QUANTILES(initial_hs_tnt, 2)[OFFSET(1)], 4) AS median_initial_hs_tnt,
  ROUND(APPROX_QUANTILES(initial_hs_tnt, 4)[OFFSET(1)], 4) AS hs_tnt_25th_percentile,
  ROUND(APPROX_QUANTILES(initial_hs_tnt, 4)[OFFSET(3)], 4) AS hs_tnt_75th_percentile,
  ROUND(APPROX_QUANTILES(initial_hs_tnt, 4)[OFFSET(3)] - APPROX_QUANTILES(initial_hs_tnt, 4)[OFFSET(1)], 4) AS hs_tnt_IQR
FROM first_hs_tnt_per_admission;
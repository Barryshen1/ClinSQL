WITH ischemic_hd_admissions AS (
  -- Get admissions for males aged 47-57 with ischemic heart disease
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS adm
    INNER JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 47 AND 57
    AND (
      -- ICD-10: I20-I25 (ischemic heart disease)
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I2[0-5]'))
      -- ICD-9: 410-414 (ischemic heart disease)
      OR (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^41[0-4]'))
    )
),
troponin_t_items AS (
  -- Get itemids for Troponin T
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin_t AS (
  -- For each qualifying admission, get the first Troponin T value
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
    INNER JOIN troponin_t_items AS tti
      ON l.itemid = tti.itemid
    INNER JOIN ischemic_hd_admissions AS adm
      ON l.subject_id = adm.subject_id AND l.hadm_id = adm.hadm_id
  WHERE
    l.valuenum IS NOT NULL
),
first_troponin_t_per_admission AS (
  -- Get only the first Troponin T per admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
  FROM first_troponin_t
),
troponin_t_above_99th AS (
  -- Only admissions where first Troponin T > 0.014 ng/mL
  SELECT
    subject_id,
    hadm_id,
    valuenum
  FROM first_troponin_t_per_admission
  WHERE rn = 1 AND valuenum > 0.014
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3
FROM troponin_t_above_99th
;
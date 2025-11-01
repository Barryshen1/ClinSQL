WITH chest_pain_ami_admissions AS (
  -- Find admissions for females aged 58-68 with chest pain or AMI
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
    p.anchor_age BETWEEN 58 AND 68
    AND p.gender = 'F'
    AND (
      -- Chest pain ICD codes (ICD-9 and ICD-10)
      REGEXP_CONTAINS(dd.long_title, r'(?i)chest pain')
      OR
      -- AMI ICD codes (ICD-9: 410.*, ICD-10: I21.*, I22.*)
      REGEXP_CONTAINS(dd.long_title, r'(?i)acute myocardial infarction')
      OR
      REGEXP_CONTAINS(dd.long_title, r'(?i)ami\b')
      OR
      REGEXP_CONTAINS(d.icd_code, r'^410') -- ICD-9 AMI
      OR
      REGEXP_CONTAINS(d.icd_code, r'^I21') -- ICD-10 AMI
      OR
      REGEXP_CONTAINS(d.icd_code, r'^I22') -- ICD-10 AMI
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
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
    JOIN troponin_t_items tti ON l.itemid = tti.itemid
    JOIN chest_pain_ami_admissions cpa ON l.subject_id = cpa.subject_id AND l.hadm_id = cpa.hadm_id
  WHERE
    l.valuenum IS NOT NULL
    AND (LOWER(l.valueuom) = 'ng/ml' OR l.valueuom IS NULL) -- Accept missing units if confident
)

SELECT
  COUNT(*) AS n_patients,
  AVG(valuenum) AS mean_troponin_t,
  STDDEV(valuenum) AS sd_troponin_t,
  MIN(valuenum) AS min_troponin_t,
  MAX(valuenum) AS max_troponin_t
FROM
  first_troponin_t
WHERE
  rn = 1
  AND valuenum > 0.01
;
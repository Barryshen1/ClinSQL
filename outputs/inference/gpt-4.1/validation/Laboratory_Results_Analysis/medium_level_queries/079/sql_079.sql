WITH chest_pain_ami_icds AS (
  -- ICD codes for chest pain and AMI (both ICD-9 and ICD-10)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- Chest pain ICD-9
    (icd_version = 9 AND (
      icd_code LIKE '7865%' -- 786.50, 786.51, etc.
    ))
    OR
    -- Chest pain ICD-10
    (icd_version = 10 AND (
      icd_code LIKE 'R07%' -- R07.9, R07.2, etc.
    ))
    OR
    -- AMI ICD-9
    (icd_version = 9 AND (
      icd_code LIKE '410%' -- 410.xx
    ))
    OR
    -- AMI ICD-10
    (icd_version = 10 AND (
      icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' -- I21.xx, I22.xx
    ))
),
troponin_t_items AS (
  -- Find itemids for Troponin T (not Troponin I)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
cohort AS (
  -- Get admissions for women aged 82-92 with chest pain or AMI
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN chest_pain_ami_icds icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
initial_troponin_t AS (
  -- For each admission in the cohort, get the first Troponin T value >0.01 ng/mL
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_items tti
    ON l.itemid = tti.itemid
  JOIN cohort c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE
    l.valuenum IS NOT NULL
    AND LOWER(l.valueuom) = 'ng/ml'
)
, first_troponin_t AS (
  -- Get the first Troponin T per admission
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_charttime
  FROM initial_troponin_t
  GROUP BY subject_id, hadm_id
)
, cohort_initial_troponin AS (
  -- Join to get the value for the first Troponin T per admission
  SELECT
    i.subject_id,
    i.hadm_id,
    i.charttime,
    i.valuenum
  FROM initial_troponin_t i
  JOIN first_troponin_t f
    ON i.subject_id = f.subject_id AND i.hadm_id = f.hadm_id AND i.charttime = f.first_charttime
  WHERE i.valuenum > 0.01
)
SELECT
  COUNT(*) AS n_patients,
  MIN(valuenum) AS min_troponin_t,
  MAX(valuenum) AS max_troponin_t,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS p25_troponin_t,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS p50_troponin_t,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75_troponin_t
FROM cohort_initial_troponin
;
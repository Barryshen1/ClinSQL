WITH pe_icd_codes AS (
  -- Identify ICD codes for pulmonary embolism
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '4151%' OR LOWER(long_title) LIKE '%pulmonary embolism%'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'I26%' OR LOWER(long_title) LIKE '%pulmonary embolism%'))
),
pe_patients AS (
  -- Female ICU patients aged 65-75 with PE diagnosis
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.subject_id = diag.subject_id AND icu.hadm_id = diag.hadm_id
  JOIN pe_icd_codes pe
    ON diag.icd_code = pe.icd_code AND diag.icd_version = pe.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
),
first_icu_stays AS (
  -- Only first ICU stay per hospital admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM pe_patients
  )
  WHERE rn = 1
),
diagnostic_proc_codes AS (
  -- Diagnostic procedures ICD codes
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%diagnostic%'
),
proc_counts AS (
  -- Count diagnostic procedures within 72h of ICU admission for each first ICU stay
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    COUNT(DISTINCT proc.icd_code) AS procedure_count
  FROM first_icu_stays icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON icu.subject_id = proc.subject_id
    AND icu.hadm_id = proc.hadm_id
    AND proc.chartdate >= icu.intime
    AND proc.chartdate < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  LEFT JOIN diagnostic_proc_codes diagproc
    ON proc.icd_code = diagproc.icd_code AND proc.icd_version = diagproc.icd_version
  WHERE diagproc.icd_code IS NOT NULL
    OR proc.icd_code IS NULL -- include patients with zero procedures
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
),
add_mortality AS (
  -- Add hospital mortality flag
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.intime,
    p.outtime,
    p.los,
    p.procedure_count,
    a.hospital_expire_flag
  FROM proc_counts p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
),
with_quartiles AS (
  -- Assign quartiles based on procedure_count
  SELECT *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM add_mortality
)
SELECT
  quartile,
  COUNT(*) AS N,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(los),2) AS mean_icu_los_days,
  ROUND(AVG(hospital_expire_flag)*100,1) AS hospital_mortality_percent
FROM with_quartiles
GROUP BY quartile
ORDER BY quartile;
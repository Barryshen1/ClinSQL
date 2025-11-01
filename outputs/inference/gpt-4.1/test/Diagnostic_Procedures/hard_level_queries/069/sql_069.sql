WITH pe_patients AS (
  -- Find male ICU patients age 44-54 with PE diagnosis
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON icu.subject_id = diag.subject_id AND icu.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND (
      -- ICD-10 PE: I26.x
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I26%')
      -- ICD-9 PE: 4151x
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '4151%')
    )
),
first_icu_stay AS (
  -- For each patient/hadm_id, select first ICU stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_intime,
    icu_outtime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY icu_intime ASC) AS rn
    FROM pe_patients
  )
  WHERE rn = 1
),
procedure_counts AS (
  -- Count distinct procedures in first 72 ICU hours
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.icu_intime,
    f.icu_outtime,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON f.subject_id = p.subject_id
    AND f.hadm_id = p.hadm_id
    AND p.chartdate >= f.icu_intime
    AND p.chartdate < TIMESTAMP_ADD(f.icu_intime, INTERVAL 72 HOUR)
  GROUP BY f.subject_id, f.hadm_id, f.stay_id, f.icu_intime, f.icu_outtime
),
patient_info AS (
  -- Add LOS and mortality
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.procedure_count,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los,
    adm.hospital_expire_flag
  FROM procedure_counts pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pc.subject_id = adm.subject_id AND pc.hadm_id = adm.hadm_id
),
quintiles AS (
  -- Assign quintiles by procedure count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS procedure_quintile
  FROM patient_info
)
SELECT
  procedure_quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(procedure_count),2) AS avg_procedure_count,
  ROUND(AVG(hospital_los),2) AS avg_hospital_los,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS mortality_percent
FROM quintiles
GROUP BY procedure_quintile
ORDER BY procedure_quintile;
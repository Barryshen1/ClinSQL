WITH patients_filtered AS (
  SELECT 
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
),
admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
),
stroke_diagnosis AS (
  SELECT DISTINCT
    di.hadm_id,
    TRUE AS has_hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%intracerebral hemorrhage%'
     OR LOWER(d.long_title) LIKE '%hemorrhagic stroke%'
     OR (di.icd_version = 10 AND di.icd_code LIKE 'I61%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'I62%')
),
icu_stays_first AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    intime,
    outtime,
    los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
),
icu_first_stay AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    intime,
    outtime,
    los
  FROM icu_stays_first
  WHERE rn = 1
),
diagnostic_procs_72h AS (
  SELECT 
    pe.hadm_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  JOIN icu_first_stay i ON pe.stay_id = i.stay_id
  WHERE pe.starttime >= i.intime 
    AND pe.starttime <= i.intime + INTERVAL '72' HOUR
    AND LOWER(pe.ordercategoryname) = 'diagnostic'
  GROUP BY pe.hadm_id
),
outcome_data AS (
  SELECT 
    a.hadm_id,
    COALESCE(dp.proc_count, 0) AS proc_count,
    i.los AS icu_los,
    a.hospital_expire_flag,
    COALESCE(s.has_hemorrhagic_stroke, FALSE) AS has_hemorrhagic_stroke
  FROM admissions_with_age a
  JOIN icu_first_stay i ON a.hadm_id = i.hadm_id
  LEFT JOIN diagnostic_procs_72h dp ON a.hadm_id = dp.hadm_id
  LEFT JOIN stroke_diagnosis s ON a.hadm_id = s.hadm_id
)
SELECT
  has_hemorrhagic_stroke,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS diagnostic_proc_90th_percentile,
  AVG(icu_los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
FROM outcome_data
GROUP BY has_hemorrhagic_stroke
ORDER BY has_hemorrhagic_stroke;
WITH amI_diagnoses AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%acute myocardial infarction%'
     OR d.icd_code IN (
       'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 
       'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9',
       'I23.0', 'I23.1', 'I23.2', 'I23.3', 'I23.4', 'I23.5', 'I23.6', 'I23.7', 'I23.8', 'I23.9'
     )
),

first_icu_stay AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    intime, 
    outtime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
),

patients_filtered AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),

ami_cohort AS (
  SELECT DISTINCT pf.*
  FROM patients_filtered pf
  JOIN amI_diagnoses am ON pf.hadm_id = am.hadm_id
),

non_ami_cohort AS (
  SELECT DISTINCT pf.*
  FROM patients_filtered pf
  LEFT JOIN amI_diagnoses am ON pf.hadm_id = am.hadm_id
  WHERE am.hadm_id IS NULL
),

ami_with_first_icu AS (
  SELECT am.*, fis.stay_id, fis.intime, fis.outtime
  FROM ami_cohort am
  JOIN first_icu_stay fis ON am.hadm_id = fis.hadm_id AND fis.rn = 1
),

non_ami_with_first_icu AS (
  SELECT nma.*, fis.stay_id, fis.intime, fis.outtime
  FROM non_ami_cohort nma
  JOIN first_icu_stay fis ON nma.hadm_id = fis.hadm_id AND fis.rn = 1
),

ami_procedures AS (
  SELECT 
    awfi.subject_id,
    awfi.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM ami_with_first_icu awfi
  JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON awfi.stay_id = pe.stay_id
    AND pe.starttime >= awfi.intime
    AND pe.starttime <= awfi.intime + INTERVAL 72 HOUR
  GROUP BY awfi.subject_id, awfi.stay_id
),

ami_stats AS (
  SELECT 
    PERCENTILE_CONT(distinct_procedures, 0.9) OVER () AS p90_distinct_procedures,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM ami_with_first_icu awfi
  LEFT JOIN ami_procedures ap ON awfi.stay_id = ap.stay_id
),

non_ami_stats AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM non_ami_with_first_icu
)

SELECT 
  a.p90_distinct_procedures,
  a.mean_los_days AS ami_mean_los_days,
  a.mortality_rate AS ami_mortality_rate,
  n.mean_los_days AS non_ami_mean_los_days,
  n.mortality_rate AS non_ami_mortality_rate
FROM ami_stats a
CROSS JOIN non_ami_stats n
LIMIT 1;
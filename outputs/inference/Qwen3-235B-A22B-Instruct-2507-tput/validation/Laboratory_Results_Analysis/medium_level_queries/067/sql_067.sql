WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
),

ami_admissions AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag, pa.age_at_admission
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%myocardial infarction%'
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE '410%')
    AND di.seq_num = 1  -- Primary diagnosis
),

troponin_t_values AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),

first_troponin_filtered AS (
  SELECT
    am.subject_id,
    am.hadm_id,
    am.admittime,
    am.dischtime,
    am.hospital_expire_flag,
    am.age_at_admission,
    tt.valuenum AS first_troponin_t
  FROM ami_admissions am
  INNER JOIN troponin_t_values tt
    ON am.hadm_id = tt.hadm_id
  WHERE tt.rn = 1
    AND tt.valuenum > 0.01
)

SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(hadm_id) AS admission_count,
  ROUND(AVG(age_at_admission), 2) AS mean_age,
  ROUND(AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 86400), 2) AS mean_los_days,
  ROUND(AVG(first_troponin_t), 4) AS mean_first_troponin_t,
  ROUND(MIN(first_troponin_t), 4) AS min_first_troponin_t,
  ROUND(MAX(first_troponin_t), 4) AS max_first_troponin_t,
  SUM(hospital_expire_flag) AS in_hospital_deaths,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 3) AS mortality_rate
FROM first_troponin_filtered;
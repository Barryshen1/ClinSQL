WITH first_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hospital_expire_flag IS NOT NULL
),
patients_with_age AS (
  SELECT 
    subject_id,
    anchor_year,
    anchor_age,
    gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_year IS NOT NULL
    AND anchor_age IS NOT NULL
    AND gender = 'F'
),
pneumonia_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),
cohort AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag,
    EXTRACT(YEAR FROM fa.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM first_admissions fa
  JOIN patients_with_age p ON fa.subject_id = p.subject_id
  JOIN pneumonia_diagnoses pd ON fa.hadm_id = pd.hadm_id
  WHERE fa.rn = 1
    AND EXTRACT(YEAR FROM fa.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 83 AND 93
)
SELECT 
  COUNT(DISTINCT subject_id) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  (SUM(hospital_expire_flag) * 100.0) / COUNT(DISTINCT subject_id) AS mortality_rate
FROM cohort;
WITH hf_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    -- Compute age at admission: year(admittime) - (anchor_year - anchor_age)
    EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE d.long_title LIKE '%heart failure%' 
    OR d.icd_code LIKE 'I50%' 
    OR d.icd_code LIKE '428%'
),
first_hf_admission AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    gender,
    age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM hf_admissions
),
index_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    gender,
    age_at_admission
  FROM first_hf_admission
  WHERE rn = 1
    AND gender = 'F'
    AND age_at_admission BETWEEN 38 AND 48
    AND hospital_expire_flag = 0  -- Exclude those who died during index admission
),
readmissions AS (
  SELECT 
    i.subject_id,
    i.hadm_id AS index_hadm,
    i.dischtime,
    COUNT(DISTINCT readm.hadm_id) AS has_readmission
  FROM index_admissions i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` readm
    ON i.subject_id = readm.subject_id
    AND readm.admittime > i.dischtime
    AND readm.admittime <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY)
    AND readm.hadm_id != i.hadm_id   -- Ensure it's a different admission
  GROUP BY i.subject_id, i.hadm_id, i.dischtime
)
SELECT 
  COUNT(*) AS total_index_admissions,
  SUM(has_readmission) AS total_readmissions,
  ROUND(100.0 * SUM(has_readmission) / COUNT(*), 2) AS readmission_rate_percent
FROM readmissions;
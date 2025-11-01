WITH patients_filtered AS (
  SELECT 
    subject_id,
    anchor_year,
    anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 75 AND 85
),
sepsis_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Calculate age at admission: birth_year = anchor_year - anchor_age
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_code LIKE 'A40.%' 
    AND dd.icd_code != 'A40.0'   -- exclude septic shock
    AND dd.icd_version = 10      -- ICD-10
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_year, p.anchor_age
),
comorbidities AS (
  SELECT 
    p.subject_id,
    -- CKD: N18, N19
    MAX(CASE WHEN d.icd_code IN ('N18', 'N19') THEN 1 ELSE 0 END) AS CKD_present,
    -- Diabetes: E10-E14
    MAX(CASE WHEN d.icd_code BETWEEN 'E10' AND 'E14' THEN 1 ELSE 0 END) AS diabetes_present,
    -- AFib: I48
    MAX(CASE WHEN d.icd_code = 'I48' THEN 1 ELSE 0 END) AS AFib_present,
    -- Hypertension: I10-I15
    MAX(CASE WHEN d.icd_code BETWEEN 'I10' AND 'I15' THEN 1 ELSE 0 END) AS hypertension_present
  FROM patients_filtered p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10
  GROUP BY p.subject_id
),
sepsis_cohort AS (
  SELECT 
    s.*,
    c.CKD_present,
    c.diabetes_present,
    c.AFib_present,
    c.hypertension_present,
    CASE WHEN s.los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS LOS_group
  FROM sepsis_admissions s
  LEFT JOIN comorbidities c ON s.subject_id = c.subject_id
  WHERE s.age_at_admission BETWEEN 75 AND 85  -- Ensure age at sepsis admission is 75-85
),
comorbidity_list AS (
  SELECT 'CKD' AS comorbidity
  UNION ALL SELECT 'diabetes'
  UNION ALL SELECT 'AFib'
  UNION ALL SELECT 'hypertension'
)
SELECT
  s.LOS_group,
  c.comorbidity,
  CASE 
    WHEN c.comorbidity = 'CKD' THEN s.CKD_present
    WHEN c.comorbidity = 'diabetes' THEN s.diabetes_present
    WHEN c.comorbidity = 'AFib' THEN s.AFib_present
    WHEN c.comorbidity = 'hypertension' THEN s.hypertension_present
  END AS status,
  COUNT(*) AS num_patients,
  SUM(s.hospital_expire_flag) AS deaths,
  SUM(s.hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate
FROM sepsis_cohort s
CROSS JOIN comorbidity_list c
GROUP BY s.LOS_group, c.comorbidity, status
ORDER BY s.LOS_group, c.comorbidity, status;
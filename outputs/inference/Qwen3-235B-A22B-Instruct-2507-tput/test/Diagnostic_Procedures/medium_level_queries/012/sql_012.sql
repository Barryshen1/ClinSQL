WITH patients_age AS (
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
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age p ON a.subject_id = p.subject_id
),
acs_diagnoses AS (
  SELECT 
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND d.icd_code LIKE 'I21%'
),
echo_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_hcpcs
  WHERE code IN (
    '76999', '93306', '93307', '93308', '93312', '93313', '93314', 
    '93315', '93317', '93318', '93320', '93321', '93325', '93350', '93351'
  )
),
ultrasound_procedures AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN echo_codes e ON h.hcpcs_cd = e.code
  GROUP BY h.hadm_id
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.los_days,
    CASE 
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group
  FROM admissions_with_age a
  INNER JOIN acs_diagnoses acs ON a.hadm_id = acs.hadm_id
  WHERE a.age_at_admission BETWEEN 35 AND 45
    AND a.los_days BETWEEN 1 AND 7
),
cohort_with_us AS (
  SELECT 
    c.hadm_id,
    c.los_group,
    COALESCE(u.procedure_count, 0) AS us_count
  FROM cohort c
  LEFT JOIN ultrasound_procedures u ON c.hadm_id = u.hadm_id
)
SELECT
  los_group,
  COUNT(*) AS patient_count,
  AVG(us_count) AS mean_ultrasounds_per_admission
FROM cohort_with_us
GROUP BY los_group
ORDER BY los_group;
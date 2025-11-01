WITH first_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
filtered_patients AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM fa.admittime) AS admityear
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  WHERE fa.rn = 1
    AND p.gender = 'F'
),
age_filtered AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    anchor_age - (anchor_year - admityear) AS age_at_admission
  FROM filtered_patients
  WHERE (anchor_age - (anchor_year - admityear)) BETWEEN 35 AND 45
),
cabg_patients AS (
  SELECT 
    af.subject_id,
    af.hadm_id,
    af.hospital_expire_flag
  FROM age_filtered af
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    WHERE pi.hadm_id = af.hadm_id
      AND (
        (pi.icd_version = 9 AND pi.icd_code LIKE '361%')
        OR
        (pi.icd_version = 10 AND pi.icd_code LIKE '021%')
      )
  )
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate
FROM cabg_patients;
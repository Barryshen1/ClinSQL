WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    a.admission_location,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
),
age_calculated AS (
  SELECT *,
    anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year AS age_at_admission
  FROM first_admissions
  WHERE rn = 1
),
principal_stroke AS (
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    di.icd_code,
    di.icd_version
  FROM 
    age_calculated ac
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON ac.hadm_id = di.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE 
    di.seq_num = 1
    AND di.icd_code IN ('430', '431', '432', 'I60', 'I61', 'I62')
    AND di.icd_version IN (9, 10)
)
SELECT 
  COUNT(*) AS cohort_count
FROM 
  principal_stroke ps
INNER JOIN 
  age_calculated ac
  ON ps.subject_id = ac.subject_id AND ps.hadm_id = ac.hadm_id
WHERE 
  ac.age_at_admission BETWEEN 68 AND 78;
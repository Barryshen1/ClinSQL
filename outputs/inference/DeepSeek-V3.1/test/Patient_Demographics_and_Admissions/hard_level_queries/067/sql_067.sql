WITH bowel_obstruction_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    icd_version = 10 AND
    (long_title LIKE '%bowel obstruction%' OR 
     long_title LIKE '%intestinal obstruction%' OR
     long_title LIKE '%ileus%')
),
cohort_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.insurance,
    adm.admission_location,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.anchor_age BETWEEN 43 AND 53
    AND pat.gender = 'F'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND adm.dischtime IS NOT NULL
),
principal_dx AS (
  SELECT 
    dx.subject_id,
    dx.hadm_id,
    dx.icd_code,
    dx.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  WHERE dx.seq_num = 1
),
qualified_admissions AS (
  SELECT 
    ca.*,
    ROW_NUMBER() OVER (PARTITION BY ca.subject_id ORDER BY ca.admittime) AS admission_rank
  FROM cohort_admissions ca
  INNER JOIN principal_dx dx
    ON ca.hadm_id = dx.hadm_id AND ca.subject_id = dx.subject_id
  INNER JOIN bowel_obstruction_codes boc
    ON dx.icd_code = boc.icd_code AND dx.icd_version = boc.icd_version
)
SELECT COUNT(hadm_id) AS count_index_admissions
FROM qualified_admissions
WHERE admission_rank = 1;
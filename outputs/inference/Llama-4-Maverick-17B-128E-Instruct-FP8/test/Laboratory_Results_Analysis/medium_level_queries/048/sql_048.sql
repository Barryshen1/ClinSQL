WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 55 AND 65
),
admissions_ami AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Myocardial infarction%' AND diag.icd_version = 10
),
hs_tnt_measurements AS (
  SELECT p.subject_id, a.hadm_id, l.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN admissions_ami a ON l.hadm_id = a.hadm_id
  JOIN patients_filtered p ON l.subject_id = p.subject_id
  WHERE l.itemid = 50821  
),
first_hs_tnt AS (
  SELECT hadm_id, valuenum, subject_id
  FROM hs_tnt_measurements
  WHERE rn = 1 AND valuenum > 0.01
)
SELECT 
  COUNT(DISTINCT subject_id) as patient_count,
  COUNT(DISTINCT hadm_id) as admission_count,
  AVG(valuenum) as mean_hs_tnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] as median_hs_tnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] as q1_hs_tnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] as q3_hs_tnt
FROM first_hs_tnt;
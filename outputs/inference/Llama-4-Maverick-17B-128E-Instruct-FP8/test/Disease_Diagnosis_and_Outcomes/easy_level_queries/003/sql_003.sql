WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 40 AND 50
),
primary_diagnosis AS (
  SELECT d.hadm_id, d.icd_code, dicd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd 
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE d.seq_num = 1
),
admission_filter AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, 
         EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_filter p ON a.subject_id = p.subject_id
  INNER JOIN primary_diagnosis pd ON a.hadm_id = pd.hadm_id
  WHERE LOWER(pd.long_title) LIKE '%ischemic%' OR LOWER(pd.long_title) LIKE '%acs%'
)
SELECT APPROX_QUANTILES(los, 100)[OFFSET(25)] AS percentile_25_los
FROM admission_filter;
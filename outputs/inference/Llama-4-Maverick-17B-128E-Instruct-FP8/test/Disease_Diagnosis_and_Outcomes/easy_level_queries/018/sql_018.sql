WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 45 AND 55
),
stroke_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN filtered_patients p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10 AND seq_num = 1  
    AND icd_code LIKE 'I61%'  
  )
)
SELECT STDDEV(DATE_DIFF(dischtime, admittime, DAY)) AS sd_length_of_stay
FROM stroke_admissions;
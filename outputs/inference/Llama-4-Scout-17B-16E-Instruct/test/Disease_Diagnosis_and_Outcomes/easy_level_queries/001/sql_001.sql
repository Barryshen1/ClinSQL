WITH 
  eligible_patients AS (
    SELECT p.subject_id, p.anchor_age, p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 86 AND 96
  ),
  
  target_admissions AS (
    SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN eligible_patients ep ON a.subject_id = ep.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    WHERE 
      di.icd_code IN ('530.7', '531.0', '531.1', '531.2', '532.0', '532.1', '532.2', '533.0', '533.1', '533.2',
                      '491.21', '492.21', '493.21')
  )

SELECT 
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_length_of_stay
FROM target_admissions;
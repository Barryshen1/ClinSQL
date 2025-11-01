WITH sepsis_admissions AS (
  SELECT DISTINCT
    a.hadm_id, 
    a.subject_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE 
    p.gender = 'M'  -- Male patients
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'A40%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'A41%') OR
      (d.icd_version = 9 AND d.icd_code = '038') OR
      (d.icd_version = 9 AND d.icd_code = '720.8')
    )
),
creatinine_candidates AS (
  SELECT 
    s.hadm_id,
    MAX(l.valuenum) AS max_creatinine
  FROM sepsis_admissions s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON s.hadm_id = l.hadm_id AND s.subject_id = l.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
    ON l.itemid = dl.itemid
  WHERE 
    dl.label LIKE '%creatinine%' 
    AND dl.category = 'Blood'  -- Filter for blood tests
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN s.admittime AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
  GROUP BY s.hadm_id
)
SELECT 
  MAX(max_creatinine) AS max_creatinine
FROM creatinine_candidates;
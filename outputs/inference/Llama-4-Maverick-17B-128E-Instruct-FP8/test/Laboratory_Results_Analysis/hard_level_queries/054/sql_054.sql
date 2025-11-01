WITH 
ami_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 38 AND 48
  AND a.admission_type = 'EMERGENCY'  
  AND dicd.long_title LIKE '%Acute myocardial infarction%'
),
lab_instability AS (
  SELECT ap.subject_id, ap.hadm_id,
         COUNT(CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 END) AS lab_abnormalities
  FROM ami_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ap.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN ap.admittime AND TIMESTAMP_ADD(ap.admittime, INTERVAL 72 HOUR)
  GROUP BY ap.subject_id, ap.hadm_id
),
quartiles AS (
  SELECT subject_id, hadm_id, lab_abnormalities,
         NTILE(4) OVER (ORDER BY lab_abnormalities) AS quartile
  FROM lab_instability
),
results AS (
  SELECT q.quartile,
         AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)) AS avg_los_hours,
         SUM(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality
  FROM quartiles q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  GROUP BY q.quartile
)
SELECT * FROM results
ORDER BY quartile;
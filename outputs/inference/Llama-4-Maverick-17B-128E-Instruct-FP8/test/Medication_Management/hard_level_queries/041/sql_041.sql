WITH hf_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
  AND dicd.long_title LIKE '%HEART FAILURE%'
),
med_complexity AS (
  SELECT p.hadm_id, COUNT(DISTINCT p.drug) AS med_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN hf_patients hf ON p.hadm_id = hf.hadm_id
  WHERE p.starttime BETWEEN hf.admittime AND TIMESTAMP_ADD(hf.admittime, INTERVAL 7 DAY)
  GROUP BY p.hadm_id
),
quintiles AS (
  SELECT hadm_id, med_count,
         NTILE(5) OVER (ORDER BY med_count) AS quintile
  FROM med_complexity
),
stats AS (
  SELECT 
    q.quintile,
    COUNT(q.hadm_id) AS patient_count,
    MIN(m.med_count) AS min_med_count,
    MAX(m.med_count) AS max_med_count,
    AVG(TIMESTAMP_DIFF(hf.dischtime, hf.admittime, DAY)) AS mean_los,
    SUM(CASE WHEN hf.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(q.hadm_id) AS in_hospital_mortality
  FROM quintiles q
  INNER JOIN med_complexity m ON q.hadm_id = m.hadm_id
  INNER JOIN hf_patients hf ON q.hadm_id = hf.hadm_id
  GROUP BY q.quintile
)
SELECT * FROM stats
ORDER BY quintile;
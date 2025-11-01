WITH 
patients_filtered AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 45 AND 55
),

multi_trauma_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%trauma%' OR dicd.long_title LIKE '%fracture%'  
),

med_complexity AS (
  SELECT pf.hadm_id, COUNT(DISTINCT p.drug) AS num_meds
  FROM patients_filtered pf
  JOIN multi_trauma_patients mtp ON pf.hadm_id = mtp.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON pf.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN pf.admittime AND TIMESTAMP_ADD(pf.admittime, INTERVAL 7 DAY)
  GROUP BY pf.hadm_id
),

tertiles AS (
  SELECT hadm_id, num_meds, 
         NTILE(3) OVER (ORDER BY num_meds) AS tertile
  FROM med_complexity
),

stats AS (
  SELECT 
    t.tertile,
    COUNT(t.hadm_id) AS num_admissions,
    AVG(t.num_meds) AS mean_med_complexity,
    MIN(t.num_meds) AS min_med_complexity,
    MAX(t.num_meds) AS max_med_complexity,
    AVG(TIMESTAMP_DIFF(pf.dischtime, pf.admittime, DAY)) AS mean_los,
    SUM(CASE WHEN pf.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(t.hadm_id) * 100 AS mortality_percent,
    SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = pf.subject_id AND a2.admittime BETWEEN pf.dischtime AND TIMESTAMP_ADD(pf.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END) / COUNT(t.hadm_id) * 100 AS readmission_percent
  FROM tertiles t
  JOIN patients_filtered pf ON t.hadm_id = pf.hadm_id
  GROUP BY t.tertile
)

SELECT * FROM stats
ORDER BY tertile;
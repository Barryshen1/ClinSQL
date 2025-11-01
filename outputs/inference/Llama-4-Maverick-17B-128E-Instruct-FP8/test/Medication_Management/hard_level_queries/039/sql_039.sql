WITH patient_info AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 87 AND 97
),
ich_patients AS (
  SELECT DISTINCT p.hadm_id
  FROM patient_info p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Intracranial hemorrhage%'
),
med_complexity AS (
  SELECT p.hadm_id, COUNT(DISTINCT CONCAT(pr.drug, pr.route)) AS med_complexity
  FROM patient_info p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.hadm_id = pr.hadm_id
  WHERE pr.starttime <= TIMESTAMP_ADD(p.admittime, INTERVAL 48 HOUR)
  AND p.hadm_id IN (SELECT hadm_id FROM ich_patients)
  GROUP BY p.hadm_id
),
quartiles AS (
  SELECT hadm_id, med_complexity, NTILE(4) OVER (ORDER BY CAST(med_complexity AS FLOAT64)) AS quartile
  FROM med_complexity
),
admissions_data AS (
  SELECT q.quartile, COUNT(DISTINCT q.hadm_id) AS admissions,
         MIN(m.med_complexity) AS min_med_complexity, MAX(m.med_complexity) AS max_med_complexity,
         AVG(DATETIME_DIFF(p.dischtime, p.admittime, HOUR)) AS avg_los_hours,
         SUM(CASE WHEN p.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) * 100 AS mortality_percent,
         SUM(CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
           WHERE a2.subject_id = p.subject_id AND a2.hadm_id != p.hadm_id AND a2.admittime BETWEEN p.dischtime AND TIMESTAMP_ADD(p.dischtime, INTERVAL 30 DAY)
         ) THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) * 100 AS readmission_percent
  FROM quartiles q
  JOIN med_complexity m ON q.hadm_id = m.hadm_id
  JOIN patient_info p ON q.hadm_id = p.hadm_id
  GROUP BY q.quartile
)
SELECT quartile, admissions, min_med_complexity, max_med_complexity, avg_los_hours, mortality_percent, readmission_percent
FROM admissions_data
ORDER BY quartile;
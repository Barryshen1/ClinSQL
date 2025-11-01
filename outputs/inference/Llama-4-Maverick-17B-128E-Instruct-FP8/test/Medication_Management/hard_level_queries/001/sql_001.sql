WITH 
cardiac_arrest_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON h.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Cardiac arrest%' AND h.admittime IS NOT NULL
),
patient_data AS (
  SELECT p.subject_id, h.hadm_id, 
         p.anchor_age + DATE_DIFF(DATE(h.admittime), DATE(p.anchor_year, 1, 1), DAY) / 365.25 AS age_at_admission,
         h.admittime, h.dischtime, h.deathtime,
         COUNT(DISTINCT pr.pharmacy_id) AS medication_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` h ON p.subject_id = h.subject_id
  INNER JOIN cardiac_arrest_patients cap ON h.hadm_id = cap.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON h.hadm_id = pr.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 76 AND 86
  AND pr.starttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 7 DAY)
  GROUP BY p.subject_id, h.hadm_id, p.anchor_age, h.admittime, h.dischtime, h.deathtime
),
quintiles AS (
  SELECT hadm_id, medication_count,
         NTILE(5) OVER (ORDER BY medication_count) AS quintile
  FROM patient_data
),
stats AS (
  SELECT q.quintile,
         COUNT(DISTINCT q.hadm_id) AS patient_count,
         AVG(TIMESTAMP_DIFF(pd.dischtime, pd.admittime, DAY)) AS avg_los,
         MIN(TIMESTAMP_DIFF(pd.dischtime, pd.admittime, DAY)) AS min_los,
         MAX(TIMESTAMP_DIFF(pd.dischtime, pd.admittime, DAY)) AS max_los,
         AVG(CASE WHEN pd.deathtime IS NOT NULL THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_pct,
         AVG(CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` h2
           WHERE h2.subject_id = pd.subject_id AND h2.admittime > pd.dischtime
           AND TIMESTAMP_DIFF(h2.admittime, pd.dischtime, DAY) <= 30
         ) THEN 1 ELSE 0 END) * 100 AS thirty_day_readmission_pct
  FROM quintiles q
  INNER JOIN patient_data pd ON q.hadm_id = pd.hadm_id
  GROUP BY q.quintile
)
SELECT 
  quintile,
  patient_count,
  avg_los, min_los, max_los,
  in_hospital_mortality_pct,
  thirty_day_readmission_pct
FROM stats
ORDER BY quintile;
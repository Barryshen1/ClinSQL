WITH 
-- Identify heart failure icd codes
heart_failure_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Heart failure%'
),

-- Filter patients and admissions
patients_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (SELECT icd_code FROM heart_failure_icd)
    )
),

-- Filter serum creatinine events within the first 24h of admission
creatinine_events AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON le.itemid = di.itemid
  WHERE di.label = 'Serum Creatinine'
)

-- Find maximum serum creatinine
SELECT 
  pa.subject_id, 
  pa.hadm_id, 
  MAX(ce.valuenum) AS max_creatinine
FROM patients_admissions pa
JOIN creatinine_events ce 
  ON pa.subject_id = ce.subject_id AND pa.hadm_id = ce.hadm_id
  AND ce.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 1 DAY)
GROUP BY pa.subject_id, pa.hadm_id
ORDER BY max_creatinine DESC;
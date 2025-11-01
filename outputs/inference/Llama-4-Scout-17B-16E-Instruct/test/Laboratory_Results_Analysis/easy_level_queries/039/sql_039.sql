WITH 
-- Identify male patients with pneumonia and their peak serum creatinine
pneumonia_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    MAX(CASE WHEN l.itemid = 220050 AND l.valuenum IS NOT NULL THEN l.valuenum END) AS peak_creatinine
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.icd_code LIKE '481%'  -- Pneumonia ICD code
    AND l.itemid = 220050  -- Serum creatinine
  GROUP BY 
    a.subject_id, a.hadm_id
  HAVING 
    MAX(CASE WHEN l.itemid = 220050 AND l.valuenum IS NOT NULL THEN l.valuenum END) IS NOT NULL
)

-- Select the standard deviation of peak creatinine
SELECT 
  STDDEV(peak_creatinine) AS std_dev
FROM 
  pneumonia_patients;
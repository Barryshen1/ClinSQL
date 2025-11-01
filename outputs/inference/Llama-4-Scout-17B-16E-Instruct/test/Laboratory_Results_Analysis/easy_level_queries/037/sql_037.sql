WITH 
-- Identify male patients with sepsis
sepsis_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
  AND d.icd_code LIKE '% sepsis %'
),

-- Extract peak platelet count for each patient
platelet_counts AS (
  SELECT 
    subject_id,
    MAX(CASE 
      WHEN d.label = 'Platelet Count' THEN valuenum 
      ELSE NULL 
    END) AS peak_platelet_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON le.itemid = d.itemid
  WHERE 
    le.subject_id IN (SELECT subject_id FROM sepsis_patients)
    AND le.valuenum IS NOT NULL
  GROUP BY 
    subject_id
)

-- Calculate 75th percentile of peak platelet count
SELECT 
  APPROX_QUANTILES(peak_platelet_count, 100)[OFFSET(75)] AS percentile_75
FROM 
  platelet_counts;
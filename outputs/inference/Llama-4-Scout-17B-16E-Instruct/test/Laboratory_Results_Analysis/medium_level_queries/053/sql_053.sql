WITH 
-- Identify first Troponin I measurement for each admission
first_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE 
    di.label = 'Troponin I' 
    AND le.valuenum > 0  -- Ensure value is numeric and positive
),
-- Filter patients and admissions of interest
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND d.icd_code LIKE '410.1%'  -- ICD-9 code for ACS
)
-- Join to get first Troponin I measurements for patients of interest
SELECT 
  COUNT(DISTINCT fti.subject_id) AS patient_count,
  COUNT(fti.hadm_id) AS admission_count,
  AVG(fti.valuenum) AS mean_troponin,
  STDDEV(fti.valuenum) AS sd_troponin,
  MIN(fti.valuenum) AS min_troponin,
  MAX(fti.valuenum) AS max_troponin
FROM 
  first_troponin fti
JOIN 
  patients_of_interest poi ON fti.subject_id = poi.subject_id AND fti.hadm_id = poi.hadm_id
WHERE 
  fti.valuenum > 0.04;
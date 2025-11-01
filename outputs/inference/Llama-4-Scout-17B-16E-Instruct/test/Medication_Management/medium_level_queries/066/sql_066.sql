WITH 
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.admittime <= TIMESTAMP_SUB(a.dischtime, INTERVAL 72 HOUR)
),

comorbidities AS (
  SELECT 
    subject_id, 
    hadm_id, 
    ARRAY_AGG(icd_code) AS icd_codes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    subject_id, 
    hadm_id
),

glp1_prescriptions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    drug, 
    starttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%glp-1%' 
    OR LOWER(drug) LIKE '%exenatide%' 
    OR LOWER(drug) LIKE '%liraglutide%' 
    OR LOWER(drug) LIKE '%dulaglutide%' 
    OR LOWER(drug) LIKE '%semaglutide%'
)

SELECT 
  COUNT(DISTINCT CASE WHEN gp.starttime <= TIMESTAMP_ADD(poi.admittime, INTERVAL 72 HOUR) THEN poi.hadm_id END) * 100.0 / COUNT(DISTINCT poi.hadm_id) AS percent_glp1_first_72h,
  COUNT(DISTINCT CASE WHEN gp.starttime >= TIMESTAMP_SUB(poi.dischtime, INTERVAL 12 HOUR) THEN poi.hadm_id END) * 100.0 / COUNT(DISTINCT poi.hadm_id) AS percent_glp1_final_12h,
  COUNT(DISTINCT CASE WHEN gp.starttime <= TIMESTAMP_ADD(poi.admittime, INTERVAL 72 HOUR) THEN poi.hadm_id END) * 100.0 / COUNT(DISTINCT poi.hadm_id) 
    - COUNT(DISTINCT CASE WHEN gp.starttime >= TIMESTAMP_SUB(poi.dischtime, INTERVAL 12 HOUR) THEN poi.hadm_id END) * 100.0 / COUNT(DISTINCT poi.hadm_id) AS absolute_difference_pp
FROM 
  patients_of_interest poi
  JOIN comorbidities c ON poi.subject_id = c.subject_id AND poi.hadm_id = c.hadm_id
  LEFT JOIN glp1_prescriptions gp ON poi.hadm_id = gp.hadm_id AND poi.subject_id = gp.subject_id
WHERE 
  EXISTS (SELECT 1 FROM UNNEST(c.icd_codes) AS code WHERE code LIKE '250.%')  -- T2DM
  AND EXISTS (SELECT 1 FROM UNNEST(c.icd_codes) AS code WHERE code LIKE '402.%' OR code LIKE '428.%');  -- Heart Failure;
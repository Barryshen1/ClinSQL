WITH 
-- Identify target population
target_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (
        SELECT icd_code 
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
        WHERE long_title IN ('Diabetes mellitus', 'Heart failure')
      )
      GROUP BY hadm_id
      HAVING COUNT(DISTINCT icd_code) = 2
    )
),

-- Identify GLP-1 starts
glp1_starts AS (
  SELECT subject_id, hadm_id, starttime,
         CASE 
           WHEN drug LIKE '%exenatide%' OR drug LIKE '%liraglutide%' OR drug LIKE '%dulaglutide%' OR drug LIKE '%semaglutide%' THEN 'GLP-1'
         END AS medication_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug_type = 'subcutaneous'
    AND (drug LIKE '%exenatide%' OR drug LIKE '%liraglutide%' OR drug LIKE '%dulaglutide%' OR drug LIKE '%semaglutide%')
),

-- Timing of GLP-1 starts
glp1_timing AS (
  SELECT tp.hadm_id,
         TIMESTAMP_DIFF(ts.starttime, a.admittime, HOUR) AS hours_from_admit,
         TIMESTAMP_DIFF(a.dischtime, ts.starttime, HOUR) AS hours_before_discharge
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON tp.hadm_id = a.hadm_id
  LEFT JOIN glp1_starts ts 
    ON tp.hadm_id = ts.hadm_id
    AND ts.medication_type = 'GLP-1'
)

-- Calculate prevalence
SELECT 
  COUNT(CASE WHEN hours_from_admit BETWEEN 0 AND 24 THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS first_24h_glp1_starts_prevalence,
  COUNT(CASE WHEN hours_before_discharge BETWEEN 0 AND 12 THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS final_12h_glp1_starts_prevalence,
  COUNT(DISTINCT hadm_id) AS total_patients
FROM glp1_timing;
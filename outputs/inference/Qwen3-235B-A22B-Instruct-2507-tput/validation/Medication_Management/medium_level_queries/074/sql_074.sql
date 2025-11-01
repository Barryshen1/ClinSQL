WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    -- Calculate age at admission
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 48 AND 58
    -- Must have diabetes (ICD-10 E08-E13) and heart failure (I50)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id 
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'E08%' 
             OR d.icd_code LIKE 'E09%' 
             OR d.icd_code LIKE 'E10%' 
             OR d.icd_code LIKE 'E11%' 
             OR d.icd_code LIKE 'E13%')
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id 
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50%'
    )
),
glp1_prescriptions AS (
  SELECT 
    p.hadm_id,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  WHERE 
    (LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%exenatide%')
    AND (LOWER(p.route) LIKE '%subcut%'
         OR LOWER(p.route) LIKE '%sub q%'
         OR LOWER(p.route) LIKE '%sub-q%'
         OR LOWER(p.route) = 'sc'
         OR LOWER(p.route) LIKE 'sc %'
         OR LOWER(p.route) LIKE '% sc')
),
first_24h_starts AS (
  SELECT DISTINCT hadm_id
  FROM glp1_prescriptions g
  INNER JOIN eligible_admissions e ON g.hadm_id = e.hadm_id
  WHERE g.starttime >= e.admittime 
    AND g.starttime <= DATETIME_ADD(e.admittime, INTERVAL 24 HOUR)
),
final_12h_starts AS (
  SELECT DISTINCT hadm_id
  FROM glp1_prescriptions g
  INNER JOIN eligible_admissions e ON g.hadm_id = e.hadm_id
  WHERE g.starttime >= DATETIME_ADD(e.dischtime, INTERVAL -12 HOUR)
    AND g.starttime <= e.dischtime
)
SELECT
  (SELECT COUNT(*) FROM first_24h_starts) * 100.0 / (SELECT COUNT(*) FROM eligible_admissions) AS pct_first_24h,
  (SELECT COUNT(*) FROM final_12h_starts) * 100.0 / (SELECT COUNT(*) FROM eligible_admissions) AS pct_final_12h;
WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 52 AND 62
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10 AND icd_code LIKE 'E11%'  -- Adjusted to LIKE 'E11%' to capture more specific diabetes codes
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10 AND icd_code LIKE 'I50%'  
  )
),
glp1_meds AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%semaglutide%'  -- Using LOWER for case-insensitive matching
),
med_admin AS (
  SELECT c.subject_id, c.hadm_id,
         SUM(CASE WHEN p.starttime <= c.admittime + INTERVAL 1 DAY THEN 1 ELSE 0 END) AS glp1_first24,
         SUM(CASE WHEN p.starttime >= c.dischtime - INTERVAL 2 DAY THEN 1 ELSE 0 END) AS glp1_last48
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  JOIN glp1_meds g ON p.drug = g.drug
  GROUP BY c.subject_id, c.hadm_id
)
SELECT 
  COUNT(CASE WHEN glp1_first24 > 0 THEN 1 END) / COUNT(*) AS prevalence_first24,
  COUNT(CASE WHEN glp1_last48 > 0 THEN 1 END) / COUNT(*) AS prevalence_last48,
  (COUNT(CASE WHEN glp1_last48 > 0 THEN 1 END) / COUNT(*)) - (COUNT(CASE WHEN glp1_first24 > 0 THEN 1 END) / COUNT(*)) AS absolute_change,
  CASE
    WHEN COUNT(CASE WHEN glp1_first24 > 0 THEN 1 END) = 0 THEN NULL
    ELSE SAFE_DIVIDE((COUNT(CASE WHEN glp1_last48 > 0 THEN 1 END) / COUNT(*)) - (COUNT(CASE WHEN glp1_first24 > 0 THEN 1 END) / COUNT(*)), 
                     (COUNT(CASE WHEN glp1_first24 > 0 THEN 1 END) / COUNT(*)))
  END AS relative_change
FROM med_admin;
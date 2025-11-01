WITH 
-- Step 1: Identify patients with DKA diagnosis
dka_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 84 AND 94
    AND dicd.long_title LIKE '%Diabetic ketoacidosis%'
),

-- Step 2: Identify hyperkalemia-risk drug interactions
hyperkalemia_drugs AS (
  -- For simplicity, let's assume we're checking for certain drug classes known to cause hyperkalemia
  -- e.g., Potassium-sparing diuretics, ACE inhibitors, ARBs, etc.
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug LIKE '%Spironolactone%' OR drug LIKE '%Lisinopril%'  -- Example drugs; real query should include all relevant drug names or classes
),

-- Step 3: Calculate medication complexity (e.g., number of unique medications per patient)
med_complexity AS (
  SELECT p.hadm_id, COUNT(DISTINCT p.drug) AS num_drugs
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN dka_patients dp ON p.hadm_id = dp.hadm_id
  GROUP BY p.hadm_id
),

-- Step 4: Calculate LOS and Mortality
patient_outcomes AS (
  SELECT a.hadm_id, 
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
         CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality_hospital
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN dka_patients dp ON a.hadm_id = dp.hadm_id
)

-- Main query to compare outcomes between those with and without hyperkalemia-risk drug interactions
SELECT 
  CASE WHEN hd.hadm_id IS NOT NULL THEN 'With Hyperkalemia Risk' ELSE 'Without Hyperkalemia Risk' END AS hyperkalemia_risk_group,
  AVG(mc.num_drugs) AS mean_medication_complexity,
  PERCENTILE_CONT(mc.num_drugs, 0.75) OVER () AS top_complexity_quartile,
  AVG(po.los) AS mean_los,
  AVG(po.mortality_hospital) AS mortality_rate
FROM dka_patients dp
LEFT JOIN hyperkalemia_drugs hd ON dp.hadm_id = hd.hadm_id
JOIN med_complexity mc ON dp.hadm_id = mc.hadm_id
JOIN patient_outcomes po ON dp.hadm_id = po.hadm_id
GROUP BY hyperkalemia_risk_group

-- To report LOS and mortality for the top complexity quartile
UNION ALL

SELECT 
  'Top Complexity Quartile' AS group_name,
  NULL AS mean_medication_complexity,
  NULL AS top_complexity_quartile,
  AVG(los) AS mean_los,
  AVG(mortality_hospital) AS mortality_rate
FROM (
  SELECT po.hadm_id, po.los, po.mortality_hospital, 
         PERCENT_RANK() OVER (ORDER BY mc.num_drugs DESC) AS complexity_rank
  FROM patient_outcomes po
  JOIN med_complexity mc ON po.hadm_id = mc.hadm_id
) sub
WHERE complexity_rank <= 0.25;
WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
),
aki_patients AS (
  -- Simplified AKI identification using creatinine levels from labevents
  SELECT DISTINCT l.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label LIKE '%Creatinine%' AND l.valuenum > 1.2  -- Simplified AKI criterion
),
-- Creating a CTE to manually categorize drugs
drug_labels AS (
  SELECT 'Morphine' AS drug_name, 'CNS-Depressant' AS category UNION ALL
  SELECT 'Furosemide', 'Nephrotoxic' UNION ALL
  SELECT 'Gentamicin', 'Nephrotoxic' UNION ALL
  SELECT 'Lorazepam', 'CNS-Depressant'
  -- Add more drugs and their categories as needed
),
drug_exposure AS (
  SELECT p.hadm_id, 
         COUNT(DISTINCT CASE WHEN dl.category = 'CNS-Depressant' THEN p.drug END) AS num_cns_depressant,
         COUNT(DISTINCT CASE WHEN dl.category = 'Nephrotoxic' THEN p.drug END) AS num_nephrotoxic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  LEFT JOIN drug_labels dl ON p.drug = dl.drug_name
  GROUP BY p.hadm_id
),
med_complexity AS (
  SELECT hadm_id, COUNT(*) AS num_drugs, COUNT(DISTINCT drug) AS num_unique_drugs
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY hadm_id
),
outcomes AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los,
         a.deathtime IS NOT NULL AS died_in_hospital
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
cohort AS (
  SELECT p.subject_id, a.hadm_id,
         COALESCE(de.num_cns_depressant, 0) > 0 AND COALESCE(de.num_nephrotoxic, 0) > 0 AS exposed_to_both,
         mc.num_drugs, mc.num_unique_drugs,
         o.los, o.died_in_hospital
  FROM patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN aki_patients ap ON a.hadm_id = ap.hadm_id
  LEFT JOIN drug_exposure de ON a.hadm_id = de.hadm_id
  LEFT JOIN med_complexity mc ON a.hadm_id = mc.hadm_id
  JOIN outcomes o ON a.hadm_id = o.hadm_id
)
SELECT 
  exposed_to_both,
  APPROX_QUANTILES(num_drugs, 100) AS drugs_quartiles,
  AVG(num_drugs) AS mean_num_drugs,
  AVG(los) AS mean_los,
  SUM(CAST(died_in_hospital AS INT64)) / COUNT(*) AS mortality,
  APPROX_QUANTILES(num_drugs, 100)[OFFSET(75)] AS top_quartile_num_drugs,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS top_quartile_los
FROM cohort
GROUP BY exposed_to_both;
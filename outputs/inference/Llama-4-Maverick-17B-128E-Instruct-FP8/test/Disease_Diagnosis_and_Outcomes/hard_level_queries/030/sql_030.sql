WITH 
-- Step 1: Filter patients and calculate age
patients_filtered AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 64 AND 74
),

-- Step 2: Identify patients with upper GI bleeding
upper_gi_bleeding AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Gastrointestinal hemorrhage%' OR dicd.long_title LIKE '%Upper GI bleed%'
),

-- Step 3: Calculate diagnosis count and major complication for each hadm_id
diagnosis_count AS (
  SELECT hadm_id, COUNT(*) as count_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
major_complication AS (
  SELECT hadm_id, COUNT(*) as count_major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Complication%'  -- Simplified condition for major complication
  GROUP BY hadm_id
),

-- Step 4: Calculate composite risk score
composite_risk_score AS (
  SELECT a.hadm_id, 
         COALESCE(dc.count_diagnoses, 0) as count_diagnoses,
         COALESCE(mc.count_major_complication, 0) as count_major_complication,
         COALESCE(dc.count_diagnoses, 0) + 20 * COALESCE(mc.count_major_complication, 0) as composite_score
  FROM upper_gi_bleeding a
  LEFT JOIN diagnosis_count dc ON a.hadm_id = dc.hadm_id
  LEFT JOIN major_complication mc ON a.hadm_id = mc.hadm_id
),

-- Step 5: Calculate quintiles of composite risk score
quintiles AS (
  SELECT hadm_id, composite_score,
         NTILE(5) OVER (ORDER BY composite_score) as quintile
  FROM composite_risk_score
),

-- Step 6: Calculate outcomes
admissions_info AS (
  SELECT a.hadm_id, a.dischtime, a.deathtime, p.dod,
         DATE_DIFF(COALESCE(a.deathtime, p.dod), a.dischtime, DAY) as days_to_death,
         DATE_DIFF(a.dischtime, a.admittime, DAY) as los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN patients_filtered pf ON a.subject_id = pf.subject_id  -- Filter by age and gender
),

outcomes AS (
  SELECT q.quintile,
         COUNT(*) as n,
         AVG(q.composite_score) as mean_score,
         AVG(IF(ai.days_to_death <= 30, 1, 0)) * 100 as mortality_30_day_percent,
         AVG(IF(mc.count_major_complication > 0, 1, 0)) * 100 as major_complication_percent,
         APPROX_QUANTILE(ai.los, 0.5) as median_los
  FROM quintiles q
  JOIN composite_risk_score crs ON q.hadm_id = crs.hadm_id
  JOIN admissions_info ai ON q.hadm_id = ai.hadm_id
  LEFT JOIN major_complication mc ON q.hadm_id = mc.hadm_id
  WHERE ai.days_to_death IS NULL OR ai.days_to_death > 0  -- Filter out patients who died on the same day as discharge
  GROUP BY q.quintile
)

SELECT quintile, n, mean_score, mortality_30_day_percent, major_complication_percent, median_los
FROM outcomes
ORDER BY quintile;
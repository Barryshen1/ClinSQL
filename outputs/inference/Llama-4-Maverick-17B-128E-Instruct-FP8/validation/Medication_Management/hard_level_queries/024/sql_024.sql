WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code LIKE 'S%'  -- Simplified trauma diagnosis identification
  )
),

-- Step 2: Determine ICU stay details
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN cohort ON i.subject_id = cohort.subject_id AND i.hadm_id = cohort.hadm_id
),

-- Step 3: Assess medication complexity within the first 24 hours
med_complexity AS (
  SELECT i.stay_id, COUNT(DISTINCT p.drug) AS num_meds
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN icu_stays i ON p.hadm_id = i.hadm_id
  WHERE p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.stay_id
),

-- Step 4: Identify serotonergic interaction risk
serotonergic_risk AS (
  SELECT DISTINCT i.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN icu_stays i ON p.hadm_id = i.hadm_id
  WHERE p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  AND LOWER(p.drug) LIKE '%serotonin%'  -- Simplified serotonergic medication identification
),

-- Step 5: Calculate LOS and Mortality
outcomes AS (
  SELECT 
    i.stay_id,
    i.outtime - i.intime AS los,
    a.hospital_expire_flag AS mortality
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)

-- Final analysis
SELECT 
  risk_group,
  PERCENTILE_CONT(num_meds, 0.25) OVER () AS complexity_quartile_1,
  PERCENTILE_CONT(num_meds, 0.5) OVER () AS complexity_median,
  PERCENTILE_CONT(num_meds, 0.75) OVER () AS complexity_quartile_3,
  AVG(complexity_percentile) OVER () AS avg_complexity_percentile,
  AVG(los) AS avg_los,
  AVG(mortality) AS avg_mortality
FROM (
  SELECT 
    m.stay_id,
    m.num_meds,
    PERCENT_RANK() OVER (ORDER BY m.num_meds) AS complexity_percentile,
    CASE WHEN s.stay_id IS NOT NULL THEN 'Serotonergic Risk' ELSE 'No Serotonergic Risk' END AS risk_group,
    o.los,
    o.mortality
  FROM med_complexity m
  JOIN outcomes o ON m.stay_id = o.stay_id
  LEFT JOIN serotonergic_risk s ON m.stay_id = s.stay_id
)
GROUP BY risk_group

UNION ALL

SELECT 
  'Top Quartile' AS risk_group,
  NULL, NULL, NULL, NULL,
  AVG(los) AS avg_los,
  AVG(mortality) AS avg_mortality
FROM (
  SELECT 
    m.stay_id,
    m.num_meds,
    o.los,
    o.mortality
  FROM med_complexity m
  JOIN outcomes o ON m.stay_id = o.stay_id
)
WHERE num_meds >= (SELECT PERCENTILE_CONT(num_meds, 0.75) FROM med_complexity);
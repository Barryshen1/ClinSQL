WITH 
-- Step 1: Identify the cohort (female inpatients aged 48-58)
cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime,
         p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
),

-- Step 2: Determine hemorrhagic stroke patients
hemorrhagic_stroke AS (
  SELECT DISTINCT a.hadm_id
  FROM cohort a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%hemorrhagic stroke%' OR dicd.long_title LIKE '%intracerebral hemorrhage%'
),

-- Step 3 & 4: Medication complexity and serotonergic drugs within first 48 hours
med_complexity AS (
  SELECT c.hadm_id, 
         COUNT(DISTINCT p.drug) AS total_drugs,
         SUM(CASE WHEN LOWER(p.drug) LIKE '%sertraline%' OR LOWER(p.drug) LIKE '%fluoxetine%' THEN 1 ELSE 0 END) AS serotonergic_drugs
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),

-- Step 5: Outcomes (LOS, mortality)
outcomes AS (
  SELECT c.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los,
         a.hospital_expire_flag AS hospital_mortality
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
),

-- Prepare final data with complexity percentile
final_data AS (
  SELECT 
    CASE WHEN hs.hadm_id IS NOT NULL THEN 'Hemorrhagic Stroke' ELSE 'Control' END AS group_category,
    CASE WHEN mc.serotonergic_drugs >= 2 THEN '>= 2 Serotonergic Drugs' ELSE '< 2 Serotonergic Drugs' END AS serotonergic_category,
    PERCENT_RANK() OVER (PARTITION BY CASE WHEN hs.hadm_id IS NOT NULL THEN 'Hemorrhagic Stroke' ELSE 'Control' END ORDER BY mc.total_drugs) AS complexity_percentile,
    o.los AS avg_los,
    o.hospital_mortality
  FROM cohort c
  LEFT JOIN hemorrhagic_stroke hs ON c.hadm_id = hs.hadm_id
  JOIN med_complexity mc ON c.hadm_id = mc.hadm_id
  JOIN outcomes o ON c.hadm_id = o.hadm_id
)

-- Final analysis
SELECT 
  group_category,
  serotonergic_category,
  CASE WHEN complexity_percentile <= 0.75 THEN 'Bottom 75%' ELSE 'Top 25%' END AS complexity_group,
  AVG(avg_los) AS avg_los,
  AVG(hospital_mortality) AS avg_hospital_mortality
FROM final_data
GROUP BY group_category, serotonergic_category, 
         CASE WHEN complexity_percentile <= 0.75 THEN 'Bottom 75%' ELSE 'Top 25%' END
ORDER BY group_category, serotonergic_category;
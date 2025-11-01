WITH 
-- Filter admissions for male patients aged 79-89 with Pulmonary Embolism (PE)
pe_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.deathtime, p.dod, 
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 79 AND 89
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE dicd.long_title LIKE '%Pulmonary embolism%'
    )
),

-- Calculate comorbidity score (example using count of distinct diagnoses)
comorbidity_scores AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- Calculate percentile of comorbidity score for PE admissions
comorbidity_percentiles AS (
  SELECT hadm_id, 
         PERCENT_RANK() OVER (ORDER BY comorbidity_count) AS comorbidity_percentile
  FROM comorbidity_scores
  WHERE hadm_id IN (SELECT hadm_id FROM pe_admissions)
),

-- Identify 30-day mortality, cardiac, and neurologic complications
outcomes AS (
  SELECT 
    pa.hadm_id,
    pa.subject_id,
    -- 30-day mortality
    CASE 
      WHEN pa.deathtime IS NOT NULL AND DATETIME_DIFF(pa.deathtime, pa.admittime, DAY) <= 30 THEN 1
      WHEN pa.dod IS NOT NULL AND DATETIME_DIFF(pa.dod, pa.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    -- Cardiac complication (example: using ICD codes starting with 'I')
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = pa.hadm_id AND d.icd_code LIKE 'I%'
    ) AS cardiac_complication,
    -- Neurologic complication (example: using ICD codes starting with 'G')
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = pa.hadm_id AND d.icd_code LIKE 'G%'
    ) AS neurologic_complication,
    -- Survival days
    COALESCE(DATETIME_DIFF(pa.deathtime, pa.admittime, DAY), DATETIME_DIFF(pa.dod, pa.admittime, DAY), 1000) AS survival_days,
    cp.comorbidity_percentile
  FROM pe_admissions pa
  JOIN comorbidity_percentiles cp ON pa.hadm_id = cp.hadm_id
)

SELECT 
  PERCENTILE_CONT(mortality_30d, 0.5) AS median_30d_mortality,
  AVG(CAST(cardiac_complication AS INT64)) AS cardiac_complication_rate,
  AVG(CAST(neurologic_complication AS INT64)) AS neurologic_complication_rate,
  PERCENTILE_CONT(survival_days, 0.5) AS median_survival_days,
  PERCENTILE_CONT(comorbidity_percentile, 0.5) AS median_comorbidity_percentile
FROM outcomes
WHERE comorbidity_percentile >= 0.75;  -- Top quartile comorbidity burden;
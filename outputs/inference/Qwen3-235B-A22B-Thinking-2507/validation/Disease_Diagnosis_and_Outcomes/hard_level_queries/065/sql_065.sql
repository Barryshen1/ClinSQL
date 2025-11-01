WITH dvt_population AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- 90-day mortality
    CASE WHEN p.dod IS NOT NULL 
              AND DATETIME_DIFF(CAST(p.dod AS DATETIME), CAST(a.admittime AS DATETIME), DAY) <= 90 
         THEN 1 ELSE 0 END AS mortality_90d,
    -- Major complication: mortality or PE
    CASE WHEN p.dod IS NOT NULL 
              AND DATETIME_DIFF(CAST(p.dod AS DATETIME), CAST(a.admittime AS DATETIME), DAY) <= 90 OR
              EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
                      WHERE d.hadm_id = a.hadm_id AND d.icd_code LIKE 'I26%')
         THEN 1 ELSE 0 END AS major_complication,
    -- Hospital LOS in days
    DATETIME_DIFF(CAST(a.dischtime AS DATETIME), CAST(a.admittime AS DATETIME), DAY) AS los_days,
    -- Comorbidity count (simplified)
    (SELECT COUNT(DISTINCT icd_code) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
     WHERE d.hadm_id = a.hadm_id) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND (d.icd_code LIKE 'I80%' OR d.icd_code LIKE 'I82%')
    )
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 71 AND 81
),

high_comorbidity AS (
  SELECT *
  FROM dvt_population
  WHERE comorbidity_count > 3  -- High comorbidity threshold
),

general_population AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- 90-day mortality
    CASE WHEN p.dod IS NOT NULL 
              AND DATETIME_DIFF(CAST(p.dod AS DATETIME), CAST(a.admittime AS DATETIME), DAY) <= 90 
         THEN 1 ELSE 0 END AS mortality_90d,
    -- Major complication: mortality or PE
    CASE WHEN p.dod IS NOT NULL 
              AND DATETIME_DIFF(CAST(p.dod AS DATETIME), CAST(a.admittime AS DATETIME), DAY) <= 90 OR
              EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
                      WHERE d.hadm_id = a.hadm_id AND d.icd_code LIKE 'I26%')
         THEN 1 ELSE 0 END AS major_complication,
    -- Hospital LOS in days
    DATETIME_DIFF(CAST(a.dischtime AS DATETIME), CAST(a.admittime AS DATETIME), DAY) AS los_days,
    -- Comorbidity count
    (SELECT COUNT(DISTINCT icd_code) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
     WHERE d.hadm_id = a.hadm_id) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 71 AND 81
)

SELECT
  'DVT High Comorbidity' AS `group`,
  APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(50)] AS median_risk_score,
  APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(25)] AS q1_risk_score,
  APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS q3_risk_score,
  AVG(mortality_90d) AS mortality_90d_rate,
  AVG(major_complication) AS major_complication_rate,
  AVG(CASE WHEN mortality_90d = 0 THEN los_days ELSE NULL END) AS survivor_los
FROM high_comorbidity

UNION ALL

SELECT
  'General Inpatients' AS `group`,
  APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(50)] AS median_risk_score,
  APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(25)] AS q1_risk_score,
  APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS q3_risk_score,
  AVG(mortality_90d) AS mortality_90d_rate,
  AVG(major_complication) AS major_complication_rate,
  AVG(CASE WHEN mortality_90d = 0 THEN los_days ELSE NULL END) AS survivor_los
FROM general_population;
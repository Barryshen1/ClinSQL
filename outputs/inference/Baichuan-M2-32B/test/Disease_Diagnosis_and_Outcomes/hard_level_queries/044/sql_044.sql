with cardiac arrest, stratified into quartiles by composite risk score, 
-- report for each quartile: 30-day mortality, cardiovascular and neurologic complication rates, 
-- median survivor LOS, and baseline 30-day mortality for all female 59-69.

WITH eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 59 AND 69
),
cardiac_arrest_patients AS (
  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ep.subject_id = d.subject_id
    AND ep.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE dd.icd_code = 'I46.9'  -- cardiac arrest ICD-10 code
    AND dd.icd_version = 10
),
-- Compute number of diagnoses per admission as a proxy for comorbidity burden (dummy risk score)
diagnosis_counts AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
cardiac_arrest_with_risk AS (
  SELECT
    ep.*,
    dc.num_diagnoses,
    NTILE(4) OVER (ORDER BY dc.num_diagnoses) AS risk_quartile
  FROM eligible_patients ep
  INNER JOIN cardiac_arrest_patients cap
    ON ep.subject_id = cap.subject_id
    AND ep.hadm_id = cap.hadm_id
  LEFT JOIN diagnosis_counts dc
    ON ep.subject_id = dc.subject_id
    AND ep.hadm_id = dc.hadm_id
),
outcomes AS (
  SELECT
    car.*,
    -- 30-day mortality: died within 30 days of admission
    CASE 
      WHEN car.dod IS NOT NULL 
        AND DATE_DIFF(CAST(car.dod AS DATE), CAST(car.admittime AS DATE), DAY) BETWEEN 0 AND 30 
      THEN 1 
      ELSE 0 
    END AS died_30day,
    -- Cardiovascular complications (excluding cardiac arrest ICD code)
    COALESCE((
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = car.subject_id
        AND d.hadm_id = car.hadm_id
        AND d.icd_code BETWEEN 'I20' AND 'I52'
        AND d.icd_code != 'I46.9'
      LIMIT 1
    ), 0) AS has_cv_complication,
    -- Neurologic complications
    COALESCE((
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = car.subject_id
        AND d.hadm_id = car.hadm_id
        AND d.icd_code BETWEEN 'G00' AND 'G99'
      LIMIT 1
    ), 0) AS has_neuro_complication,
    -- Survivor LOS: for patients surviving beyond 30 days, in days
    CASE 
      WHEN car.dod IS NULL OR DATE_DIFF(CAST(car.dod AS DATE), CAST(car.admittime AS DATE), DAY) > 30 
      THEN DATE_DIFF(CAST(car.dischtime AS DATE), CAST(car.admittime AS DATE), DAY)
      ELSE NULL 
    END AS survivor_los
  FROM cardiac_arrest_with_risk car
),
quartile_agg AS (
  SELECT
    risk_quartile,
    COUNT(*) AS num_patients,
    SUM(died_30day) / COUNT(*) AS mortality_30day,
    AVG(has_cv_complication) AS cv_complication_rate,
    AVG(has_neuro_complication) AS neuro_complication_rate,
    PERCENTILE_CONT(survivor_los, 0.5) WITHIN GROUP (ORDER BY survivor_los) AS median_survivor_los
  FROM outcomes
  GROUP BY risk_quartile
),
baseline_mortality AS (
  SELECT
    SUM(CASE 
          WHEN dod IS NOT NULL 
            AND DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) BETWEEN 0 AND 30 
          THEN 1 
          ELSE 0 
        END) / COUNT(*) AS baseline_mortality
  FROM eligible_patients
)
SELECT
  qa.*,
  bm.baseline_mortality
FROM quartile_agg qa
CROSS JOIN baseline_mortality bm
ORDER BY risk_quartile;
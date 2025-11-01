WITH 
-- Step 1: Get female patients aged 59-69 at admission
cohort_base AS (
  SELECT 
    p.subject_id,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
),

-- Step 2: Filter for cardiac arrest admissions
cardiac_arrest AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '4275')
     OR (icd_version = 10 AND icd_code IN ('I460', 'I461', 'I468', 'I469'))
),

-- Step 3: Combine to get final cohort
cohort AS (
  SELECT cb.*
  FROM cohort_base cb
  INNER JOIN cardiac_arrest ca
    ON cb.hadm_id = ca.hadm_id
),

-- Step 4: Compute risk score (diagnosis count)
risk_score AS (
  SELECT 
    hadm_id,
    COUNT(*) AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY hadm_id
),

-- Step 5: Compute complication flags
complications AS (
  SELECT 
    d.hadm_id,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code = '412' OR d.icd_code LIKE '413%' OR d.icd_code LIKE '414%' OR d.icd_code LIKE '425%' OR d.icd_code LIKE '426%' OR d.icd_code LIKE '427%' OR d.icd_code LIKE '428%'))
            OR (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%' OR d.icd_code LIKE 'I42%' OR d.icd_code LIKE 'I43%' OR d.icd_code LIKE 'I44%' OR d.icd_code LIKE 'I45%' OR d.icd_code LIKE 'I47%' OR d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I49%' OR d.icd_code LIKE 'I50%') AND d.icd_code NOT LIKE 'I46%')
          THEN 1 ELSE 0 
        END) AS cv_comp,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND (d.icd_code LIKE '345%' OR d.icd_code LIKE '348%' OR (d.icd_code >= '430' AND d.icd_code < '439')))
            OR (d.icd_version = 10 AND (d.icd_code LIKE 'G40%' OR d.icd_code LIKE 'G41%' OR d.icd_code LIKE 'G42%' OR d.icd_code LIKE 'G43%' OR d.icd_code LIKE 'G44%' OR d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'G46%' OR d.icd_code LIKE 'G47%' OR d.icd_code LIKE 'G93%' OR (d.icd_code >= 'I60' AND d.icd_code < 'I70')))
          THEN 1 ELSE 0 
        END) AS neuro_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY d.hadm_id
),

-- Step 6: Combine all metrics
cohort_metrics AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.dod,
    r.risk_score,
    comp.cv_comp,
    comp.neuro_comp,
    -- 30-day mortality flag
    CASE 
      WHEN c.deathtime IS NOT NULL AND c.deathtime <= TIMESTAMP_ADD(c.admittime, INTERVAL 30 DAY) THEN 1
      WHEN c.dod IS NOT NULL AND c.dod <= DATE_ADD(CAST(c.admittime AS DATE), INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS mortality_30d,
    -- LOS in days (for survivors)
    DATE_DIFF(CAST(c.dischtime AS DATE), CAST(c.admittime AS DATE), DAY) AS los
  FROM cohort c
  INNER JOIN risk_score r 
    ON c.hadm_id = r.hadm_id
  INNER JOIN complications comp 
    ON c.hadm_id = comp.hadm_id
),

-- Step 7: Assign quartiles by risk score
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM cohort_metrics
)

-- Step 8: Aggregate results by quartile
SELECT 
  quartile,
  AVG(mortality_30d) AS mortality_30d_rate,
  AVG(cv_comp) AS cv_comp_rate,
  AVG(neuro_comp) AS neuro_comp_rate,
  APPROX_QUANTILES(IF(mortality_30d = 0, los, NULL), 100)[OFFSET(50)] AS median_survivor_los,
  (SELECT AVG(mortality_30d) FROM cohort_metrics) AS baseline_30d_mortality
FROM quartiles
GROUP BY quartile
ORDER BY quartile;
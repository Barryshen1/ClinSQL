WITH 
-- Define upper GI bleeding and calculate risk score
ugi_bleeding AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    p.anchor_age,
    p.gender,
    COUNT(di.icd_code) AS diagnosis_count,
    SUM(CASE WHEN di.icd_code IN ('456.0', '530.7') THEN 1 ELSE 0 END) * 20 AS complication_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 64 AND 74
    AND di.icd_code IN ('456.0', '530.7')  -- Example codes for upper GI bleeding
  GROUP BY 
    a.subject_id, 
    a.hadm_id,
    p.anchor_age,
    p.gender
),
-- Calculate composite risk score and quintiles
risk_quintiles AS (
  SELECT 
    subject_id, 
    hadm_id,
    diagnosis_count,
    complication_score,
    diagnosis_count + complication_score AS composite_score,
    NTILE(5) OVER (ORDER BY diagnosis_count + complication_score) AS quintile
  FROM 
    ugi_bleeding
),
-- Calculate outcomes
outcomes AS (
  SELECT 
    rq.hadm_id,
    rq.quintile,
    CASE 
      WHEN a.deathtime IS NOT NULL AND a.deathtime <= TIMESTAMP_ADD(a.admittime, INTERVAL 30 DAY) THEN 1 
      ELSE 0 
    END AS thirty_day_mortality,
    CASE 
      WHEN dg.drg_severity IS NOT NULL THEN 1 
      ELSE 0 
    END AS major_complication,
    COALESCE(i.los, 0) AS los
  FROM 
    risk_quintiles rq
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON rq.hadm_id = a.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.drgcodes` dg ON rq.hadm_id = dg.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON rq.hadm_id = i.hadm_id
)
-- Final aggregation
SELECT 
  o.quintile,
  COUNT(DISTINCT o.hadm_id) AS n,
  AVG(rq.composite_score) AS mean_score,
  AVG(o.thirty_day_mortality) * 100 AS thirty_day_mortality_pct,
  AVG(o.major_complication) * 100 AS major_complication_pct,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.los) AS median_los
FROM 
  outcomes o
JOIN 
  risk_quintiles rq ON o.hadm_id = rq.hadm_id
GROUP BY 
  o.quintile;
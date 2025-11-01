WITH 
  -- Identify heart failure admissions for females aged 59-69
  hf_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9', 'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.5', 'I50.6', 'I50.7', 'I50.8', 'I50.9')
      )
  ),
  
  -- Identify AKI and ARDS
  aki_ards AS (
    SELECT 
      subject_id,
      hadm_id,
      CASE 
        WHEN itemid = 220050 AND valuenum > 1.5 THEN 'AKI'
        WHEN itemid = 220179 AND valuenum > 1.5 THEN 'AKI'
        ELSE NULL
      END AS aki,
      CASE 
        WHEN itemid = 220050 AND valuenum > 3.0 THEN 'ARDS'
        WHEN itemid = 220179 AND valuenum > 3.0 THEN 'ARDS'
        ELSE NULL
      END AS ards
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE 
      itemid IN (220050, 220179)
  ),
  
  -- Calculate in-hospital mortality, AKI, and ARDS rates
  outcomes AS (
    SELECT 
      COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) AS mortality_count,
      COUNT(DISTINCT hadm_id) AS total_patients,
      SUM(CASE WHEN aki = 'AKI' THEN 1 ELSE 0 END) AS aki_count,
      SUM(CASE WHEN ards = 'ARDS' THEN 1 ELSE 0 END) AS ards_count
    FROM 
      hf_patients
    LEFT JOIN 
      aki_ards
    ON 
      hf_patients.hadm_id = aki_ards.hadm_id
  ),

  -- Calculate median survival
  survival AS (
    SELECT 
      APPROX_QUANTILES(TIMESTAMP_DIFF(hf.deathtime, hf.admittime, DAY), 0.5)[OFFSET(1)] AS median_survival
    FROM 
      hf_patients hf
    WHERE 
      hf.hospital_expire_flag = 1
  ),

  -- Composite risk score distribution (assuming based on DRG codes)
  risk_scores AS (
    SELECT 
      drg_severity
    FROM 
      `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE 
      hadm_id IN (SELECT hadm_id FROM hf_patients)
  )

SELECT 
  -- In-hospital mortality rate
  (o.mortality_count / o.total_patients) * 100 AS mortality_rate,
  -- AKI rate
  (o.aki_count / o.total_patients) * 100 AS aki_rate,
  -- ARDS rate
  (o.ards_count / o.total_patients) * 100 AS ards_rate,
  -- Median survival
  s.median_survival,
  -- Composite risk score distribution
  MIN(r.drg_severity) AS min_risk,
  APPROX_QUANTILES(r.drg_severity, 0.25)[OFFSET(1)] AS p25_risk,
  APPROX_QUANTILES(r.drg_severity, 0.5)[OFFSET(1)] AS median_risk,
  APPROX_QUANTILES(r.drg_severity, 0.75)[OFFSET(1)] AS p75_risk,
  APPROX_QUANTILES(r.drg_severity, 0.9)[OFFSET(1)] AS p90_risk,
  MAX(r.drg_severity) AS max_risk
FROM 
  outcomes o
CROSS JOIN 
  survival s
LEFT JOIN 
  risk_scores r
ON 
  TRUE;
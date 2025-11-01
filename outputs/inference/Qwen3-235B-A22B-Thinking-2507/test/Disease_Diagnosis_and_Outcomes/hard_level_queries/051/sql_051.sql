WITH acute_pancreatitis_codes AS (
  SELECT code 
  FROM UNNEST([
    'K850', 'K851', 'K852', 'K853', 'K854', 'K858', 'K859', 'K863',  -- ICD-10
    '5770'                                                           -- ICD-9
  ]) AS code
),
major_complication_codes AS (
  SELECT code 
  FROM UNNEST([
    -- Respiratory failure
    'J9600', 'J9601', 'J9602', '51881', '51882', '51884',
    -- Acute kidney injury
    'N170', 'N171', 'N172', 'N178', 'N179', '5840', '5841', '5845', '5846', '5847', '5848', '5849',
    -- Sepsis
    'A419', '0389', '99591',
    -- Shock
    'R579', '78550', '78551', '78552', '78553', '78559',
    -- Pancreatic necrosis
    'K8681', '5771'
  ]) AS code
),
cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code IN (SELECT code FROM acute_pancreatitis_codes)
        AND d.icd_version IN (9, 10)
    )
),
diagnosis_metrics AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(d.icd_code) AS diagnosis_count,
    SUM(CASE WHEN d.icd_code IN (SELECT code FROM major_complication_codes) THEN 1 ELSE 0 END) AS major_complication_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
    AND d.icd_version IN (9, 10)
  GROUP BY c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
risk_scores AS (
  SELECT 
    *,
    diagnosis_count + 5 * major_complication_count AS risk_score,
    NTILE(4) OVER (ORDER BY (diagnosis_count + 5 * major_complication_count)) AS quartile
  FROM diagnosis_metrics
),
los_data AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM risk_scores
),
quartile_results AS (
  SELECT 
    CAST(quartile AS STRING) AS quartile,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(CASE WHEN major_complication_count > 0 THEN 1 ELSE 0 END) AS major_complication_rate,
    APPROX_QUANTILES(IF(hospital_expire_flag = 0, los_days, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_survivor_los
  FROM los_data
  GROUP BY quartile
),
overall_results AS (
  SELECT 
    'overall' AS quartile,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(CASE WHEN major_complication_count > 0 THEN 1 ELSE 0 END) AS major_complication_rate,
    APPROX_QUANTILES(IF(hospital_expire_flag = 0, los_days, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_survivor_los
  FROM los_data
)
SELECT 
  quartile,
  mortality_rate,
  major_complication_rate,
  median_survivor_los
FROM quartile_results
UNION ALL
SELECT 
  quartile,
  mortality_rate,
  major_complication_rate,
  median_survivor_los
FROM overall_results
ORDER BY 
  CASE quartile
    WHEN '1' THEN 1
    WHEN '2' THEN 2
    WHEN '3' THEN 3
    WHEN '4' THEN 4
    ELSE 5
  END;
WITH cohort AS (
  -- Base cohort: females 84-94 with primary DKA diagnosis, inpatient
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = CAST(d.hadm_id AS INT64)
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')  -- Exclude OBSERVATION, NEWBORN
    AND d.seq_num = 1
    AND (
      (d.icd_code = 'E10.10' OR d.icd_code = 'E11.10') AND d.icd_version = '10'
    )
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions for LOS/mortality
    AND a.hospital_expire_flag IS NOT NULL
),

drugs AS (
  -- Medications in first 48h
  SELECT 
    c.*,
    pr.drug,
    pr.form_rx,
    pr.doses_per_24_hrs,
    pr.prod_strength
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = CAST(pr.hadm_id AS INT64)
  WHERE 
    pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 2 DAY)
    AND pr.drug IS NOT NULL
),

complexity AS (
  -- Calculate MRCI per unique drug, then sum per admission
  SELECT 
    hadm_id,
    -- Interaction flag: hyperkalemia-risk drugs (examples; extend patterns as needed)
    MAX(CASE WHEN 
      REGEXP_CONTAINS(LOWER(drug), r'(lisinopril|benazepril|enalapril|ramipril|losartan|valsartan|spironolactone|eplerenone|ibuprofen|naproxen|indomethacin|metoprolol|atenolol|propranolol|trimethoprim|ketorolac|ceftriaxone)') 
      THEN 1 ELSE 0 END) AS has_interaction,
    -- MRCI components (simplified)
    SUM(
      -- Form (1 pt for tablet/IV/capsule, etc.)
      CASE 
        WHEN LOWER(form_rx) IN ('tablet', 'cap', 'iv', 'inj') THEN 1 
        ELSE 0 
      END +
      -- Frequency (0.5-4 pts; map common)
      CASE 
        WHEN doses_per_24_hrs >= 4 THEN 4
        WHEN doses_per_24_hrs = 3 THEN 3
        WHEN doses_per_24_hrs = 2 THEN 2
        WHEN doses_per_24_hrs = 1 THEN 1
        WHEN doses_per_24_hrs IS NULL OR doses_per_24_hrs <= 0 THEN 0.5
        ELSE 0.5 
      END +
      -- Strength (0.5 if present/non-simple)
      CASE WHEN prod_strength IS NOT NULL AND SAFE_CAST(prod_strength AS FLOAT64) > 0 THEN 0.5 ELSE 0 END
    ) AS mrci_total,
    COUNT(DISTINCT drug) AS num_unique_drugs
  FROM 
    drugs
  GROUP BY 
    hadm_id
),

final_metrics AS (
  -- Join back to cohort, add LOS, percentile
  SELECT 
    c.*,
    com.has_interaction,
    com.mrci_total,
    com.num_unique_drugs,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    -- Percentile rank within cohort
    PERCENT_RANK() OVER (ORDER BY com.mrci_total ASC) * 100 AS mrci_percentile
  FROM 
    cohort c
  LEFT JOIN 
    complexity com
    ON c.hadm_id = com.hadm_id
  WHERE 
    com.mrci_total IS NOT NULL  -- At least one med
)

-- Comparisons: mean complexity and percentile by interaction group
SELECT 
  has_interaction,
  AVG(mrci_total) AS mean_complexity,
  AVG(mrci_percentile) AS mean_percentile,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mean_mortality  -- Proportion
FROM 
  final_metrics
GROUP BY 
  has_interaction

UNION ALL BY NAME

-- Top complexity quartile: LOS and mortality (overall, no group split)
SELECT 
  CAST(NULL AS INT64) AS has_interaction,
  CAST(NULL AS FLOAT64) AS mean_complexity,
  CAST(NULL AS FLOAT64) AS mean_percentile,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mean_mortality
FROM (
  SELECT *
  FROM final_metrics
  WHERE mrci_total >= (
    SELECT 
      APPROX_QUANTILES(mrci_total, 4)[OFFSET(3)]
    FROM final_metrics
  )
);
WITH 
-- Define sepsis ICD codes
sepsis_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code LIKE 'R65.2%'))
    OR
    (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code LIKE '995.9%'))
),

-- Get cohort of male patients aged 80-90 with sepsis
cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN sepsis_codes s
        ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
),

-- Get medications administered in first 24 hours (from both HOSP and ICU)
medications AS (
  -- Medications from HOSP (emar)
  SELECT 
    c.hadm_id,
    LOWER(e.medication) AS drug_name
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime >= c.admittime
    AND e.charttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  
  UNION DISTINCT
  
  -- Medications from ICU (inputevents)
  SELECT 
    c.hadm_id,
    LOWER(d.label) AS drug_name
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` i
    ON c.hadm_id = i.hadm_id
    AND i.starttime >= c.admittime
    AND i.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON i.itemid = d.itemid
),

-- Define QT-prolonging and bleeding-risk drugs
drug_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN drug_name IN (
            'amiodarone', 'sotalol', 'haloperidol', 'methadone', 
            'ciprofloxacin', 'levofloxacin', 'erythromycin', 'clarithromycin'
          ) THEN 1 
          ELSE 0 
        END) AS has_qt,
    MAX(CASE 
          WHEN drug_name IN (
            'warfarin', 'heparin', 'aspirin', 'clopidogrel', 
            'dabigatran', 'rivaroxaban', 'apixaban', 'edoxaban', 'enoxaparin'
          ) THEN 1 
          ELSE 0 
        END) AS has_bleeding
  FROM medications
  GROUP BY hadm_id
),

-- Calculate medication count and assign groups
cohort_with_metrics AS (
  SELECT 
    c.*,
    COALESCE(med_count.med_count, 0) AS med_count,
    df.has_qt,
    df.has_bleeding,
    CASE 
      WHEN df.has_qt = 1 AND df.has_bleeding = 1 THEN 1 
      ELSE 2 
    END AS group_id
  FROM cohort c
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT drug_name) AS med_count
    FROM medications
    GROUP BY hadm_id
  ) med_count ON c.hadm_id = med_count.hadm_id
  LEFT JOIN drug_flags df ON c.hadm_id = df.hadm_id
),

-- Calculate percentile ranks within groups
with_ranks AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (PARTITION BY group_id ORDER BY med_count) AS percentile_rank
  FROM cohort_with_metrics
),

-- Identify top quartile (highest 25% of medication complexity)
with_top_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (PARTITION BY group_id ORDER BY med_count DESC) AS quartile
  FROM with_ranks
)

-- Final output: distribution data and summary statistics
SELECT 
  'distribution' AS result_type,
  group_id,
  hadm_id,
  med_count,
  percentile_rank,
  CAST(NULL AS FLOAT64) AS avg_los,
  CAST(NULL AS FLOAT64) AS mortality_rate
FROM with_top_quartile

UNION ALL

SELECT 
  'summary' AS result_type,
  group_id,
  CAST(NULL AS INT64) AS hadm_id,
  CAST(NULL AS INT64) AS med_count,
  CAST(NULL AS FLOAT64) AS percentile_rank,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM with_top_quartile
WHERE quartile = 1
GROUP BY group_id;
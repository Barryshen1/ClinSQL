WITH acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    -- Calculate age at admission (MIMIC-IV standard method)
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-10: I20-I24 codes
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I2[0-4]'))
          OR 
          -- ICD-9: 410-411.99 codes
          (d.icd_version = 9 AND d.icd_code >= '410' AND d.icd_code < '412')
        )
    )
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime, l.labevent_id  -- Tie-break with labevent_id
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
    ON l.itemid = d.itemid
  INNER JOIN acs_admissions a 
    ON l.hadm_id = a.hadm_id
  WHERE d.label = 'Troponin I'  -- Standard label in d_labitems
    AND l.charttime >= a.admittime  -- Lab after admission
    AND l.valuenum IS NOT NULL  -- Numeric values only
),
filtered_admissions AS (
  SELECT 
    troponin_value
  FROM first_troponin
  WHERE rn = 1  -- First Troponin I per admission
    AND troponin_value > 0.04  -- Exceeds 99th percentile ULN (0.04 ng/mL)
)
SELECT
  COUNT(*) AS count,
  AVG(troponin_value) AS mean,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] 
    - APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS iqr
FROM filtered_admissions;
WITH 
-- Identify Troponin T lab events
troponin_t AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE 
    di.label = 'Troponin T'  
    AND le.valuenum IS NOT NULL
),

-- Filter admissions for ACS and demographics
acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    dd.long_title LIKE '%Acute coronary syndrome%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),

-- First Troponin T value for each ACS admission
first_troponin AS (
  SELECT 
    tt.hadm_id,
    MIN(tt.charttime) AS first_charttime
  FROM 
    troponin_t tt
  GROUP BY 
    tt.hadm_id
),

-- Combine to get first Troponin T value for ACS admissions
first_troponin_values AS (
  SELECT 
    tt.valuenum
  FROM 
    troponin_t tt
  JOIN 
    first_troponin ft ON tt.hadm_id = ft.hadm_id AND tt.charttime = ft.first_charttime
  JOIN 
    acs_admissions aa ON tt.hadm_id = aa.hadm_id
  WHERE 
    tt.valuenum > 0.01
)

-- Calculate median and IQR
SELECT 
  APPROX_QUANTILES(valuenum, 1000)[500] AS median,
  APPROX_QUANTILES(valuenum, 1000)[250] AS q1,
  APPROX_QUANTILES(valuenum, 1000)[750] AS q3
FROM 
  first_troponin_values;
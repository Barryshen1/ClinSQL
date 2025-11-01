WITH
-- Identify Troponin T itemids from d_labitems
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%troponin-t%'
     OR LOWER(label) LIKE '%troponin t %'
),

-- For each admission, find the earliest Troponin T lab (within the admission) and keep its value/unit
troponin_first AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC, l.storetime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  JOIN troponin_items ti
    ON l.itemid = ti.itemid
  WHERE l.valuenum IS NOT NULL
    -- restrict lab to fall within the admission window
    AND l.charttime >= a.admittime
    AND l.charttime <= a.dischtime
),
-- Keep only the initial lab per admission
troponin_initial AS (
  SELECT subject_id, hadm_id, itemid, charttime, valuenum, valueuom
  FROM troponin_first
  WHERE rn = 1
),

-- Admissions with diagnosis indicating chest pain or AMI
diag_hadm AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chest pain%'
     OR LOWER(dd.long_title) LIKE '%pain in chest%'
     OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
     OR LOWER(dd.long_title) LIKE '%acute myocardial%'
),

-- Cohort: male patients age 58-68 with qualifying diagnosis and initial troponin > 0.04 ng/mL
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ti.valuenum AS initial_troponin,
    ti.valueuom AS troponin_uom,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN diag_hadm dh
    ON a.hadm_id = dh.hadm_id
  JOIN troponin_initial ti
    ON a.hadm_id = ti.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    -- Keep troponin values > 0.04 and (preferably) in ng/mL (or if unit missing)
    AND ti.valuenum > 0.04
    AND (
         LOWER(COALESCE(ti.valueuom, '')) LIKE '%ng/ml%' OR
         ti.valueuom IS NULL OR ti.valueuom = ''
        )
)

-- Final aggregation: summary statistics
SELECT
  COUNT(*) AS admissions_count,
  COUNT(DISTINCT subject_id) AS unique_patients,
  ROUND(AVG(anchor_age), 2) AS mean_age,
  MIN(anchor_age) AS min_age,
  MAX(anchor_age) AS max_age,
  -- Troponin statistics (ng/mL)
  ROUND(AVG(initial_troponin), 4) AS mean_initial_troponin_ng_per_mL,
  ROUND(STDDEV(initial_troponin), 4) AS sd_initial_troponin,
  ROUND(APPROX_QUANTILES(initial_troponin, 100)[OFFSET(50)], 4) AS median_initial_troponin_ng_per_mL,
  MIN(initial_troponin) AS min_initial_troponin_ng_per_mL,
  MAX(initial_troponin) AS max_initial_troponin_ng_per_mL,
  -- Length of stay (days)
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(MIN(los_days), 2) AS min_los_days,
  ROUND(MAX(los_days), 2) AS max_los_days,
  -- In-hospital mortality
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths_in_hospital,
  ROUND( SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) , 4) AS in_hospital_mortality_rate
FROM cohort_admissions;
WITH 
-- Identify patients with chest pain/AMI and initial troponin T
target_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '410%'  -- AMI
        OR icd_code LIKE '786.5%'  -- Chest pain
    )
),
-- Get initial troponin T levels
troponin_levels AS (
  SELECT 
    subject_id,
    hadm_id,
    valuenum AS troponin_level
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 4569  -- Troponin T
    AND charttime = (
      SELECT 
        MIN(charttime)
      FROM 
        `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE 
        le.hadm_id = hadm_id
        AND le.itemid = 4569
    )
),
-- Calculate 99th percentile of troponin levels
troponin_percentile AS (
  SELECT 
    APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS percentile_99
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 4569
)
-- Combine patient information with troponin levels
SELECT 
  COUNT(DISTINCT tp.hadm_id) AS N,
  AVG(tp.anchor_age) AS mean_age,
  AVG(tp.los) AS mean_los,
  AVG(tl.troponin_level) AS mean_troponin,
  MIN(tl.troponin_level) AS min_troponin,
  MAX(tl.troponin_level) AS max_troponin
FROM 
  target_patients tp
JOIN 
  troponin_levels tl 
    ON tp.subject_id = tl.subject_id AND tp.hadm_id = tl.hadm_id
WHERE 
  tl.troponin_level > (SELECT percentile_99 FROM troponin_percentile);
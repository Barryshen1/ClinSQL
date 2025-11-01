WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 64 AND 74
),
diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'E08%' 
         OR icd_code LIKE 'E09%' 
         OR icd_code LIKE 'E10%' 
         OR icd_code LIKE 'E11%' 
         OR icd_code LIKE 'E13%')
),
acute_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'I502%' 
         OR icd_code LIKE 'I503%' 
         OR icd_code LIKE 'I504%' 
         OR icd_code LIKE 'I5081%' 
         OR icd_code LIKE 'I5082%' 
         OR icd_code LIKE 'I5083%' 
         OR icd_code LIKE 'I5084%')
),
qualified_patients AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN diabetes d ON c.hadm_id = d.hadm_id
  INNER JOIN acute_hf h ON c.hadm_id = h.hadm_id
),
meds_prescriptions AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime AS admin_time,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' THEN 'sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%ertugliflozin%' THEN 'sglt2'
      WHEN LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%semaglutide%' OR LOWER(drug) LIKE '%lixisenatide%' THEN 'glp1'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'tzds'
      ELSE NULL
    END AS antidiabetic_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    (LOWER(drug) LIKE '%insulin%' OR
     LOWER(drug) LIKE '%metformin%' OR
     LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' OR
     LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' OR
     LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%ertugliflozin%' OR
     LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%semaglutide%' OR LOWER(drug) LIKE '%lixisenatide%' OR
     LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%')
),
meds_inputevents AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.starttime AS admin_time,
    CASE
      WHEN LOWER(d.label) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(d.label) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(d.label) LIKE '%glipizide%' OR LOWER(d.label) LIKE '%glyburide%' OR LOWER(d.label) LIKE '%glimepiride%' THEN 'sulfonylureas'
      WHEN LOWER(d.label) LIKE '%sitagliptin%' OR LOWER(d.label) LIKE '%saxagliptin%' OR LOWER(d.label) LIKE '%linagliptin%' OR LOWER(d.label) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(d.label) LIKE '%canagliflozin%' OR LOWER(d.label) LIKE '%dapagliflozin%' OR LOWER(d.label) LIKE '%empagliflozin%' OR LOWER(d.label) LIKE '%ertugliflozin%' THEN 'sglt2'
      WHEN LOWER(d.label) LIKE '%exenatide%' OR LOWER(d.label) LIKE '%liraglutide%' OR LOWER(d.label) LIKE '%dulaglutide%' OR LOWER(d.label) LIKE '%semaglutide%' OR LOWER(d.label) LIKE '%lixisenatide%' THEN 'glp1'
      WHEN LOWER(d.label) LIKE '%pioglitazone%' OR LOWER(d.label) LIKE '%rosiglitazone%' THEN 'tzds'
      ELSE NULL
    END AS antidiabetic_class
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON i.itemid = d.itemid
  WHERE 
    (LOWER(d.label) LIKE '%insulin%' OR
     LOWER(d.label) LIKE '%metformin%' OR
     LOWER(d.label) LIKE '%glipizide%' OR LOWER(d.label) LIKE '%glyburide%' OR LOWER(d.label) LIKE '%glimepiride%' OR
     LOWER(d.label) LIKE '%sitagliptin%' OR LOWER(d.label) LIKE '%saxagliptin%' OR LOWER(d.label) LIKE '%linagliptin%' OR LOWER(d.label) LIKE '%alogliptin%' OR
     LOWER(d.label) LIKE '%canagliflozin%' OR LOWER(d.label) LIKE '%dapagliflozin%' OR LOWER(d.label) LIKE '%empagliflozin%' OR LOWER(d.label) LIKE '%ertugliflozin%' OR
     LOWER(d.label) LIKE '%exenatide%' OR LOWER(d.label) LIKE '%liraglutide%' OR LOWER(d.label) LIKE '%dulaglutide%' OR LOWER(d.label) LIKE '%semaglutide%' OR LOWER(d.label) LIKE '%lixisenatide%' OR
     LOWER(d.label) LIKE '%pioglitazone%' OR LOWER(d.label) LIKE '%rosiglitazone%')
),
all_medications AS (
  SELECT * FROM meds_prescriptions
  UNION ALL
  SELECT * FROM meds_inputevents
),
first_admin AS (
  SELECT
    subject_id,
    hadm_id,
    antidiabetic_class,
    MIN(admin_time) AS first_admin_time
  FROM all_medications
  WHERE antidiabetic_class IS NOT NULL
  GROUP BY subject_id, hadm_id, antidiabetic_class
),
time_windows AS (
  SELECT
    q.*,
    q.admittime AS window1_start,
    TIMESTAMP_ADD(q.admittime, INTERVAL 12 HOUR) AS window1_end,
    GREATEST(q.admittime, TIMESTAMP_SUB(q.dischtime, INTERVAL 48 HOUR)) AS window2_start,
    q.dischtime AS window2_end
  FROM qualified_patients q
)
SELECT
  f.antidiabetic_class,
  SUM(CASE WHEN f.first_admin_time BETWEEN t.window1_start AND t.window1_end THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT t.hadm_id) AS pct_first_12h,
  SUM(CASE WHEN f.first_admin_time BETWEEN t.window2_start AND t.window2_end THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT t.hadm_id) AS pct_final_48h
FROM first_admin f
INNER JOIN time_windows t
  ON f.hadm_id = t.hadm_id
GROUP BY f.antidiabetic_class
ORDER BY f.antidiabetic_class;
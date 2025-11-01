WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.dischtime - a.admittime >= INTERVAL '96' HOUR
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'E1%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%'
    )
),

insulin_events AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    p.starttime,
    CASE
      WHEN p.drug LIKE '%Glargine%' OR p.drug LIKE '%Detemir%' OR p.drug LIKE '%NPH%' THEN 'basal'
      WHEN p.drug LIKE '%Lispro%' OR p.drug LIKE '%Aspart%' OR p.drug LIKE '%Glulisine%' THEN 'bolus'
      WHEN p.drug LIKE '%Regular%' THEN 'sliding_scale'
      ELSE 'other'
    END AS category
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.drug LIKE '%Insulin%'
  UNION ALL
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.starttime,
    CASE
      WHEN d.label LIKE '%Glargine%' OR d.label LIKE '%Detemir%' OR d.label LIKE '%NPH%' THEN 'basal'
      WHEN d.label LIKE '%Lispro%' OR d.label LIKE '%Aspart%' OR d.label LIKE '%Glulisine%' THEN 'bolus'
      WHEN d.label LIKE '%Regular%' THEN 'sliding_scale'
      ELSE 'other'
    END AS category
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON i.itemid = d.itemid
  WHERE d.label LIKE '%Insulin%'
),

cohort_insulin AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN ie.category = 'basal' AND ie.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS basal_first_48,
    MAX(CASE WHEN ie.category = 'bolus' AND ie.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS bolus_first_48,
    MAX(CASE WHEN ie.category = 'sliding_scale' AND ie.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS sliding_first_48,
    MAX(CASE WHEN ie.category = 'basal' AND ie.starttime BETWEEN c.dischtime - INTERVAL '48' HOUR AND c.dischtime THEN 1 ELSE 0 END) AS basal_last_48,
    MAX(CASE WHEN ie.category = 'bolus' AND ie.starttime BETWEEN c.dischtime - INTERVAL '48' HOUR AND c.dischtime THEN 1 ELSE 0 END) AS bolus_last_48,
    MAX(CASE WHEN ie.category = 'sliding_scale' AND ie.starttime BETWEEN c.dischtime - INTERVAL '48' HOUR AND c.dischtime THEN 1 ELSE 0 END) AS sliding_last_48
  FROM cohort c
  LEFT JOIN insulin_events ie
    ON c.subject_id = ie.subject_id AND c.hadm_id = ie.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)

SELECT 
  'basal' AS category,
  AVG(basal_first_48) * 100 AS first_48_pct,
  AVG(basal_last_48) * 100 AS last_48_pct
FROM cohort_insulin
UNION ALL
SELECT 
  'bolus',
  AVG(bolus_first_48) * 100,
  AVG(bolus_last_48) * 100
FROM cohort_insulin
UNION ALL
SELECT 
  'sliding_scale',
  AVG(sliding_first_48) * 100,
  AVG(sliding_last_48) * 100
FROM cohort_insulin
UNION ALL
SELECT 
  'basal_bolus',
  AVG(CASE WHEN basal_first_48 = 1 AND bolus_first_48 = 1 THEN 1 ELSE 0 END) * 100,
  AVG(CASE WHEN basal_last_48 = 1 AND bolus_last_48 = 1 THEN 1 ELSE 0 END) * 100
FROM cohort_insulin;
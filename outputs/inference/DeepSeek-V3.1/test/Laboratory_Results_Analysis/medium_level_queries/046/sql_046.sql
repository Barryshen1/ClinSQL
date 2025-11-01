WITH patient_admissions AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),

diagnosed_admissions AS (
  SELECT 
    pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  WHERE 
    di.icd_code LIKE 'I21%' 
    OR di.icd_code LIKE 'I22%' 
    OR di.icd_code LIKE 'R07%'
),

troponin_events AS (
  SELECT 
    da.subject_id, 
    da.hadm_id, 
    da.admittime, 
    da.dischtime, 
    da.anchor_age,
    le.charttime, 
    le.valuenum AS troponin_value
  FROM diagnosed_admissions da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON da.hadm_id = le.hadm_id 
    AND da.subject_id = le.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.itemid = 51003  -- Troponin T
    AND le.valuenum > 0.01
),

ranked_troponin AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (
      PARTITION BY subject_id 
      ORDER BY admittime, charttime
    ) AS rn
  FROM troponin_events
)

SELECT 
  COUNT(*) AS N,
  ROUND(AVG(anchor_age), 2) AS mean_age,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS mean_los,
  COUNT(troponin_value) AS troponin_count,
  ROUND(MIN(troponin_value), 2) AS min_troponin,
  ROUND(MAX(troponin_value), 2) AS max_troponin,
  ROUND(AVG(troponin_value), 2) AS mean_troponin
FROM ranked_troponin
WHERE rn = 1;
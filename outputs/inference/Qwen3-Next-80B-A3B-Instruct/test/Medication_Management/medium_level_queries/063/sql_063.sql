WITH diabetes_hf_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.anchor_age BETWEEN 45 AND 55
    AND p.gender = 'M'
    AND (
      LOWER(d_icd.long_title) LIKE '%diabetes%'
      OR LOWER(d_icd.long_title) LIKE '%diabetic%'
    )
    AND (
      LOWER(d_icd.long_title) LIKE '%heart failure%'
      OR LOWER(d_icd.long_title) LIKE '%congestive heart failure%'
    )
),
medication_events AS (
  SELECT 
    dhp.subject_id,
    dhp.hadm_id,
    dhp.admittime,
    dhp.dischtime,
    pr.starttime,
    pr.drug,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' 
        OR LOWER(pr.drug) LIKE '%humalog%' 
        OR LOWER(pr.drug) LIKE '%lantus%' 
        OR LOWER(pr.drug) LIKE '%levemir%' 
        OR LOWER(pr.drug) LIKE '%novolog%' 
        OR LOWER(pr.drug) LIKE '%diabetic insulin%' 
      THEN 1 ELSE 0 END AS is_insulin,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%metformin%' 
        OR LOWER(pr.drug) LIKE '%glipizide%' 
        OR LOWER(pr.drug) LIKE '%glyburide%' 
        OR LOWER(pr.drug) LIKE '%sitagliptin%' 
        OR LOWER(pr.drug) LIKE '%empagliflozin%' 
        OR LOWER(pr.drug) LIKE '%canagliflozin%' 
        OR LOWER(pr.drug) LIKE '%dapagliflozin%' 
        OR LOWER(pr.drug) LIKE '%pioglitazone%' 
        OR LOWER(pr.drug) LIKE '%rosiglitazone%' 
        OR LOWER(pr.drug) LIKE '%repaglinide%' 
        OR LOWER(pr.drug) LIKE '%nateglinide%' 
        OR LOWER(pr.drug) LIKE '%chlorpropamide%' 
        OR LOWER(pr.drug) LIKE '%tolbutamide%' 
        OR LOWER(pr.drug) LIKE '%acetohexamide%' 
      THEN 1 ELSE 0 END AS is_oral_antidiabetic
  FROM diabetes_hf_patients dhp
  JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr ON dhp.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND (pr.is_insulin = 1 OR pr.is_oral_antidiabetic = 1)
),
time_windows AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    is_insulin,
    is_oral_antidiabetic,
    CASE 
      WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 'first_12h'
      WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 72 HOUR) AND dischtime THEN 'final_72h'
      ELSE 'other'
    END AS time_window
  FROM medication_events
  WHERE starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 72 HOUR) AND DATETIME_ADD(admittime, INTERVAL 12 HOUR)
),
aggregated AS (
  SELECT 
    time_window,
    SUM(is_insulin) AS insulin_initiated,
    SUM(is_oral_antidiabetic) AS oral_antidiabetic_initiated,
    COUNT(*) AS total_initiated
  FROM time_windows
  WHERE time_window IN ('first_12h', 'final_72h')
  GROUP BY time_window
)
SELECT 
  time_window,
  ROUND(100.0 * insulin_initiated / total_initiated, 2) AS insulin_rate_percent,
  ROUND(100.0 * oral_antidiabetic_initiated / total_initiated, 2) AS oral_antidiabetic_rate_percent,
  ROUND(
    100.0 * (SUM(CASE WHEN time_window = 'first_12h' THEN insulin_initiated ELSE 0 END) / 
             SUM(CASE WHEN time_window = 'first_12h' THEN total_initiated ELSE 0 END)) 
    - 
    100.0 * (SUM(CASE WHEN time_window = 'final_72h' THEN insulin_initiated ELSE 0 END) / 
             SUM(CASE WHEN time_window = 'final_72h' THEN total_initiated ELSE 0 END)), 
    2
  ) AS insulin_pp_difference
FROM aggregated
GROUP BY time_window
ORDER BY time_window;
WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1 ON a.hadm_id = d1.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d1d ON d1.icd_code = d1d.icd_code AND d1.icd_version = d1d.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2 ON a.hadm_id = d2.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d2d ON d2.icd_code = d2d.icd_code AND d2.icd_version = d2d.icd_version
  WHERE p.anchor_age BETWEEN 54 AND 64
    AND p.gender = 'F'
    AND LOWER(d1d.long_title) LIKE '%diabetes%'
    AND LOWER(d2d.long_title) LIKE '%heart failure%'
),

insulin_orders AS (
  SELECT DISTINCT p.hadm_id,
    MAX(CASE 
      WHEN p.starttime >= a.admittime AND p.starttime <= a.admittime + INTERVAL 12 HOUR THEN 1
      ELSE 0
    END) AS insulin_first_12h,
    MAX(CASE 
      WHEN p.starttime >= a.dischtime - INTERVAL 48 HOUR AND p.starttime <= a.dischtime THEN 1
      ELSE 0
    END) AS insulin_last_48h
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  JOIN eligible_patients a ON p.hadm_id = a.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
  GROUP BY p.hadm_id
),

oral_orders AS (
  SELECT DISTINCT p.hadm_id,
    MAX(CASE 
      WHEN p.starttime >= a.admittime AND p.starttime <= a.admittime + INTERVAL 12 HOUR THEN 1
      ELSE 0
    END) AS oral_first_12h,
    MAX(CASE 
      WHEN p.starttime >= a.dischtime - INTERVAL 48 HOUR AND p.starttime <= a.dischtime THEN 1
      ELSE 0
    END) AS oral_last_48h
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  JOIN eligible_patients a ON p.hadm_id = a.hadm_id
  WHERE LOWER(p.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'pioglitazone', 'rosiglitazone', 'repaglinide', 'nateglinide', 'chlorpropamide', 'tolbutamide', 'acetohexamide', 'tolazamide')
    OR LOWER(p.drug) LIKE '%sulfonylurea%'
    OR LOWER(p.drug) LIKE '%dpp-4%'
    OR LOWER(p.drug) LIKE '%sglt2%'
  GROUP BY p.hadm_id
),

prevalence AS (
  SELECT
    AVG(COALESCE(i.insulin_first_12h, 0)) * 100 AS insulin_first_12h_pct,
    AVG(COALESCE(i.insulin_last_48h, 0)) * 100 AS insulin_last_48h_pct,
    AVG(COALESCE(o.oral_first_12h, 0)) * 100 AS oral_first_12h_pct,
    AVG(COALESCE(o.oral_last_48h, 0)) * 100 AS oral_last_48h_pct
  FROM eligible_patients e
  LEFT JOIN insulin_orders i ON e.hadm_id = i.hadm_id
  LEFT JOIN oral_orders o ON e.hadm_id = o.hadm_id
)

SELECT
  insulin_first_12h_pct,
  insulin_last_48h_pct,
  insulin_last_48h_pct - insulin_first_12h_pct AS insulin_net_change_pp,
  oral_first_12h_pct,
  oral_last_48h_pct,
  oral_last_48h_pct - oral_first_12h_pct AS oral_net_change_pp
FROM prevalence;
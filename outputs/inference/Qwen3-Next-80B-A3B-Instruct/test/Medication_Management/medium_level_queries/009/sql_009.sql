WITH diabetes_hf_patients AS (
  SELECT DISTINCT p.subject_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (
      LOWER(d_icd.long_title) LIKE '%diabetes%' 
      OR d.icd_code IN ('E10','E11','E12','E13','E14')
    )
    AND (
      (LOWER(d_icd.long_title) LIKE '%heart failure%' AND LOWER(d_icd.long_title) LIKE '%acute%')
      OR d.icd_code IN ('I50.2','I50.3','I50.4','I50.9')
    )
),
medication_events AS (
  SELECT 
    p.subject_id,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' 
        OR LOWER(p.drug) LIKE '%glargine%' 
        OR LOWER(p.drug) LIKE '%lispro%' 
        OR LOWER(p.drug) LIKE '%aspart%' 
        OR LOWER(p.drug) LIKE '%detemir%' 
        OR LOWER(p.drug) LIKE '%nph%' 
        OR LOWER(p.drug) LIKE '%regular%' 
      THEN 1 ELSE 0 END AS insulin_initiated,
    CASE 
      WHEN LOWER(p.drug) IN ('metformin', 'glipizide', 'glyburide', 'pioglitazone', 'rosiglitazone', 
                            'sitagliptin', 'linagliptin', 'dapagliflozin', 'canagliflozin', 'empagliflozin', 
                            'repaglinide', 'nateglinide', 'chlorpropamide', 'tolbutamide', 'acetohexamide', 
                            'tolazamide')
      THEN 1 ELSE 0 END AS oral_agent_initiated
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  JOIN diabetes_hf_patients dhp ON p.subject_id = dhp.subject_id
  WHERE p.starttime IS NOT NULL
),
first_24h AS (
  SELECT 
    me.subject_id,
    MAX(me.insulin_initiated) AS insulin_first_24h,
    MAX(me.oral_agent_initiated) AS oral_first_24h
  FROM medication_events me
  JOIN diabetes_hf_patients dhp ON me.subject_id = dhp.subject_id
  WHERE me.starttime BETWEEN dhp.admittime AND dhp.admittime + INTERVAL 24 HOUR
  GROUP BY me.subject_id
),
final_24h AS (
  SELECT 
    me.subject_id,
    MAX(me.insulin_initiated) AS insulin_final_24h,
    MAX(me.oral_agent_initiated) AS oral_final_24h
  FROM medication_events me
  JOIN diabetes_hf_patients dhp ON me.subject_id = dhp.subject_id
  WHERE me.starttime BETWEEN dhp.dischtime - INTERVAL 24 HOUR AND dhp.dischtime
  GROUP BY me.subject_id
)
SELECT 
  ROUND(100.0 * SUM(f.insulin_first_24h) / COUNT(*), 2) AS insulin_first_24h_pct,
  ROUND(100.0 * SUM(f.insulin_final_24h) / COUNT(*), 2) AS insulin_final_24h_pct,
  ROUND(100.0 * SUM(f.insulin_final_24h) / COUNT(*) - 100.0 * SUM(f.insulin_first_24h) / COUNT(*), 2) AS insulin_diff_pp,
  ROUND(100.0 * SUM(f.oral_first_24h) / COUNT(*), 2) AS oral_first_24h_pct,
  ROUND(100.0 * SUM(f.oral_final_24h) / COUNT(*), 2) AS oral_final_24h_pct,
  ROUND(100.0 * SUM(f.oral_final_24h) / COUNT(*) - 100.0 * SUM(f.oral_first_24h) / COUNT(*), 2) AS oral_diff_pp
FROM diabetes_hf_patients dhp
LEFT JOIN first_24h f ON dhp.subject_id = f.subject_id
LEFT JOIN final_24h fn ON dhp.subject_id = fn.subject_id;
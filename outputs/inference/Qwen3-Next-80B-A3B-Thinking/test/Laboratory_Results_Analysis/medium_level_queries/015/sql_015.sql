WITH acs_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%')
),
troponin_first AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label LIKE '%troponin%t%'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t.valuenum) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY t.valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY t.valuenum) AS iqr
FROM acs_patients a
JOIN troponin_first t ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
WHERE t.rn = 1 AND t.valuenum > 0.01;
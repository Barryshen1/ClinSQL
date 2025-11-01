WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 75 AND 85
),
eligible_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM eligible_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE a.hadm_id IS NOT NULL
    AND a.hospital_expire_flag = 0
),
ecg_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ecg%' 
     OR LOWER(label) LIKE '%ekg%' 
     OR LOWER(label) LIKE '%telemetry%'
     OR LOWER(abbreviation) LIKE '%ecg%' 
     OR LOWER(abbreviation) LIKE '%ekg%' 
     OR LOWER(abbreviation) LIKE '%telemetry%'
),
procedure_counts AS (
  SELECT 
    ea.hadm_id,
    COUNT(DISTINCT pe.itemid) AS distinct_ecg_procedures
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ea.hadm_id = pe.hadm_id
    AND pe.itemid IN (SELECT itemid FROM ecg_itemids)
  GROUP BY ea.hadm_id
)
SELECT 
  PERCENTILE_CONT(distinct_ecg_procedures, 0.75) AS p75_distinct_ecg_procedures_per_hosp
FROM procedure_counts;
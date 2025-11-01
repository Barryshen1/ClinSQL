WITH 
acs_admissions AS (
  SELECT DISTINCT a.hadm_id, 
         CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_priority
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.anchor_age BETWEEN 77 AND 87
    AND d.icd_code LIKE 'I21%'  -- Simplified ACS condition for example; expand as needed
    AND d.icd_version = 10
),
icu_stays AS (
  SELECT i.hadm_id, i.stay_id, i.los,
         CASE WHEN i.los BETWEEN 1 AND 4 THEN '1-4 days'
              WHEN i.los BETWEEN 5 AND 8 THEN '5-8 days'
              ELSE 'Outside range' END AS los_category
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN acs_admissions a ON i.hadm_id = a.hadm_id
  WHERE i.los BETWEEN 1 AND 8
),
radiology_counts AS (
  SELECT i.stay_id, COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  INNER JOIN icu_stays i ON pe.stay_id = i.stay_id
  WHERE di.label LIKE '%XR%' OR di.label LIKE '%CT%'  -- Simplified; adjust based on actual item labels
  GROUP BY i.stay_id
)
SELECT 
  a.diagnosis_priority,
  i.los_category,
  AVG(rc.proc_count) AS mean_count,
  MIN(rc.proc_count) AS min_count,
  MAX(rc.proc_count) AS max_count
FROM icu_stays i
INNER JOIN acs_admissions a ON i.hadm_id = a.hadm_id
INNER JOIN radiology_counts rc ON i.stay_id = rc.stay_id
GROUP BY a.diagnosis_priority, i.los_category
ORDER BY a.diagnosis_priority, i.los_category;
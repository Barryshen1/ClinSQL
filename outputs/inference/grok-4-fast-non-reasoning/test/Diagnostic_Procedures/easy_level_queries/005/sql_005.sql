WITH echo_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%echo%' OR LOWER(label) LIKE '%echocardiography%'
),
patient_echo_counts AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_echo_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON icu.subject_id = pe.subject_id 
    AND icu.stay_id = pe.stay_id
    AND pe.itemid IN (SELECT itemid FROM echo_itemids)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND icu.intime IS NOT NULL
  GROUP BY p.subject_id
  HAVING distinct_echo_count > 0  -- Only patients with at least one echo
)
SELECT 
  PERCENTILE_CONT(distinct_echo_count, 0.75) IGNORE NULLS AS p75_distinct_echo_per_patient
FROM patient_echo_counts;
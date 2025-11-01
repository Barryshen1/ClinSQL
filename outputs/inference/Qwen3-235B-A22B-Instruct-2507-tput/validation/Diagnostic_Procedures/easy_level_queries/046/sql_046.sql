WITH mcs_procedures AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%iabp%'
     OR LOWER(label) LIKE '%ecmo%'
     OR LOWER(label) LIKE '%ventricular assist%'
     OR LOWER(category) LIKE '%circulatory support%'
),
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 80 AND 90
),
patient_mcs_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT mcs.itemid) AS distinct_mcs_count
  FROM eligible_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.subject_id = pe.subject_id
  INNER JOIN mcs_procedures mcs
    ON pe.itemid = mcs.itemid
  GROUP BY p.subject_id
)
SELECT
  MAX(distinct_mcs_count) AS max_distinct_mcs_procedures_per_patient
FROM patient_mcs_counts;
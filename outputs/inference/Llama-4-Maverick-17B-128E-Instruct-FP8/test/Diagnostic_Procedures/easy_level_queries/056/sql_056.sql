WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 43 AND 53
),
mcs_procedures AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ecmo%' OR LOWER(label) LIKE '%lvad%' OR LOWER(label) LIKE '%mechanical circulatory support%'
),
procedure_counts AS (
  SELECT p.subject_id, COUNT(DISTINCT pe.itemid) as count_procedures
  FROM patient_filter p
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON p.subject_id = pe.subject_id
  WHERE pe.itemid IN (SELECT itemid FROM mcs_procedures)
  GROUP BY p.subject_id
)
SELECT APPROX_QUANTILES(count_procedures, 100)[OFFSET(25)] AS percentile_25
FROM procedure_counts;
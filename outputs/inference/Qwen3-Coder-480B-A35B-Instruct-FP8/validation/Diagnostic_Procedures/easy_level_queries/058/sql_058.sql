WITH cohort AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
mech_support_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mechanical circulatory support%'
),
proc_counts AS (
  SELECT c.hadm_id,
         COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.hadm_id = pe.hadm_id
  WHERE pe.itemid IN (SELECT itemid FROM mech_support_items)
  GROUP BY c.hadm_id
)
SELECT
  APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(3)] AS Q3
FROM proc_counts;
WITH patient_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
echo_counts AS (
  SELECT 
    pc.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_echo_procedures
  FROM patient_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pc.subject_id = pe.subject_id
    AND pe.itemid IN (220045, 220228)  -- Standard echo itemids: transthoracic, transesophageal
  GROUP BY pc.subject_id
)
SELECT 
  PERCENTILE_CONT(distinct_echo_procedures, 0.25) AS p25_distinct_echo_procedures
FROM echo_counts;
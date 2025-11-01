WITH male_42_52 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 42 AND 52
),
valve_procedures AS (
  SELECT p.subject_id, pr.icd_code
  FROM male_42_52 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%valve%'
    AND (
      LOWER(dpr.long_title) LIKE '%repair%'
      OR LOWER(dpr.long_title) LIKE '%replacement%'
      OR LOWER(dpr.long_title) LIKE '%prosthesis%'
      OR LOWER(dpr.long_title) LIKE '%valvuloplasty%'
    )
)
, valve_counts AS (
  SELECT subject_id, COUNT(DISTINCT icd_code) AS num_valve_procs
  FROM valve_procedures
  GROUP BY subject_id
)
SELECT AVG(num_valve_procs) AS avg_distinct_valve_procedures_per_patient
FROM valve_counts;
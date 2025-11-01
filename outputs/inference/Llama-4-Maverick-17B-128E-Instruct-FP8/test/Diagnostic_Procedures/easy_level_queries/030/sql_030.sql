WITH patient_info AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 84 AND 94
),
echo_procedures AS (
  SELECT hadm_id, COUNT(DISTINCT stay_id) as num_echo  
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid = 2239  -- Verify the itemid
  GROUP BY hadm_id
),
echo_per_hadm AS (
  SELECT p.hadm_id, COALESCE(ep.num_echo, 0) as num_echo
  FROM patient_info p
  LEFT JOIN echo_procedures ep ON p.hadm_id = ep.hadm_id
)

SELECT PERCENTILE_CONT(num_echo, 0.25) AS percentile_25th
FROM echo_per_hadm;
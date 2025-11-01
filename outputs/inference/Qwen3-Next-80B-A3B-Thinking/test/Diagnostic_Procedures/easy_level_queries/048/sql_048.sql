WITH target_hadm AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
valve_counts AS (
  SELECT th.hadm_id, 
         COUNT(DISTINCT CASE WHEN d.long_title IS NOT NULL THEN p.icd_code END) AS num_valve_procs
  FROM target_hadm th
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON th.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    AND d.long_title LIKE '%valve%' 
    AND (d.long_title LIKE '%repair%' OR d.long_title LIKE '%replacement%')
  GROUP BY th.hadm_id
)
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY num_valve_procs) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_valve_procs) AS iqr
FROM valve_counts;
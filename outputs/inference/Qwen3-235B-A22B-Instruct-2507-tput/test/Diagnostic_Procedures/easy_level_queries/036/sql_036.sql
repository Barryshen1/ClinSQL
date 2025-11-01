SELECT AVG(proc_count) AS average_distinct_valve_procedures_per_patient
FROM (
  SELECT p.subject_id, COUNT(DISTINCT pi.icd_code) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON p.subject_id = pi.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(d.long_title) LIKE '%valve%'
    AND (LOWER(d.long_title) LIKE '%repair%' OR LOWER(d.long_title) LIKE '%replacement%')
  GROUP BY p.subject_id
) sub;
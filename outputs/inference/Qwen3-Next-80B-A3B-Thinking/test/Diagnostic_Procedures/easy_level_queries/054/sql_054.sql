SELECT MAX(num_procedures) AS max_distinct_procedures
FROM (
  SELECT p.subject_id, COUNT(DISTINCT p.icd_code) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE LOWER(long_title) LIKE '%echocardi%'
  ) AS echo_procs 
    ON p.icd_code = echo_procs.icd_code 
    AND p.icd_version = echo_procs.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a 
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat 
    ON a.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
  GROUP BY p.subject_id
) AS counts;
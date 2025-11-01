WITH valve_procs AS (
  SELECT
    p.subject_id,
    pr.icd_code,
    pr.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND REGEXP_CONTAINS(LOWER(dp.long_title), r'valve')
    AND (
      REGEXP_CONTAINS(LOWER(dp.long_title), r'repair') 
      OR REGEXP_CONTAINS(LOWER(dp.long_title), r'replacement')
    )
)
, counts_per_patient AS (
  SELECT
    subject_id,
    COUNT(DISTINCT CONCAT(icd_version, '-', icd_code)) AS distinct_valve_proc_count
  FROM valve_procs
  GROUP BY subject_id
)
SELECT
  AVG(distinct_valve_proc_count) AS avg_distinct_valve_procs_per_patient
FROM counts_per_patient;
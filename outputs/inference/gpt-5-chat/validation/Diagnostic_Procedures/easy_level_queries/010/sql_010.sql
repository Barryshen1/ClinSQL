WITH echo_procs AS (
  SELECT
    p.subject_id,
    pr.icd_code,
    pr.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON adm.subject_id = pr.subject_id
   AND adm.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
   AND pr.icd_version = dpr.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND UPPER(dpr.long_title) LIKE '%ECHOCARDIO%'
)
, patient_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT CONCAT(icd_code, '-', icd_version)) AS distinct_echo_procs
  FROM echo_procs
  GROUP BY subject_id
)
SELECT
  MAX(distinct_echo_procs) AS max_distinct_echo_procs
FROM patient_counts;
WITH patient_echo_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS num_echo_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.subject_id = proc.subject_id
    AND adm.hadm_id = proc.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code
    AND proc.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 81 AND 91
    AND LOWER(dicd.long_title) LIKE '%echocardi%'
  GROUP BY
    p.subject_id
)
SELECT
  MAX(num_echo_procedures) AS max_echo_procedures
FROM
  patient_echo_counts;
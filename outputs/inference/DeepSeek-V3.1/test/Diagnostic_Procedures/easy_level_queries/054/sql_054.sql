WITH echo_counts AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_echo_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.subject_id = proc.subject_id AND adm.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND dicd.long_title LIKE '%echocardiogram%'
  GROUP BY adm.subject_id, adm.hadm_id
)
SELECT MAX(num_echo_procedures) AS max_echo_procedures
FROM echo_counts;
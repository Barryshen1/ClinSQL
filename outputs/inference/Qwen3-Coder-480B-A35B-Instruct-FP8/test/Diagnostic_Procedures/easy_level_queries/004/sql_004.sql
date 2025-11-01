WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%coronary artery bypass graft%'
     OR LOWER(long_title) LIKE '%cabg%'
),
cabg_procedures AS (
  SELECT p.subject_id,
         COUNT(DISTINCT CONCAT(proc.icd_code, '_', proc.icd_version)) AS num_cabg
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN cabg_codes cc
    ON proc.icd_code = cc.icd_code
   AND proc.icd_version = cc.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
  GROUP BY p.subject_id
)
SELECT STDDEV_SAMP(num_cabg) AS stddev_cabg_per_patient
FROM cabg_procedures;
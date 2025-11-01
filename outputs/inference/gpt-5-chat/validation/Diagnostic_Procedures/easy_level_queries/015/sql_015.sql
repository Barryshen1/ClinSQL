WITH cabg_patients AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS cabg_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND UPPER(dproc.long_title) LIKE '%BYPASS%CORONARY%'
  GROUP BY p.subject_id
)
SELECT
  PERCENTILE_CONT(cabg_count, 0.25) OVER() AS p25_cabg_per_patient
FROM cabg_patients
LIMIT 1;
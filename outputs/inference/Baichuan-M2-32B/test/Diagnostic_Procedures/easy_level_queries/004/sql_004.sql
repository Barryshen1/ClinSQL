WITH patient_list AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),
cabg_procedures AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_cabg_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_version = 9
    AND icd_code LIKE '36.%'
    AND icd_code NOT LIKE '36.0%'
  GROUP BY subject_id
)
SELECT 
  STDDEV_POP(IFNULL(c.distinct_cabg_count, 0)) AS std_dev
FROM patient_list pl
LEFT JOIN cabg_procedures c
  ON pl.subject_id = c.subject_id;
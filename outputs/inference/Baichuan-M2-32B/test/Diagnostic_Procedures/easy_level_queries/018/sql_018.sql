WITH patient_procedures AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pip.icd_code) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pip
    ON p.subject_id = pip.subject_id
    AND pip.icd_version = 9
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pip.icd_code = dip.icd_code
    AND pip.icd_version = dip.icd_version
    AND (LOWER(dip.long_title) LIKE '%catheter ablation%' 
         OR LOWER(dip.long_title) LIKE '%cardioversion%')
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
  GROUP BY p.subject_id
)
SELECT
  STDDEV_POP(distinct_procedure_count) AS sd_distinct_procedures
FROM patient_procedures;
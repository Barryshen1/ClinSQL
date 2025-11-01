WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
procedure_counts AS (
  SELECT 
    tp.subject_id,
    COUNT(DISTINCT picd.icd_code) AS distinct_procedure_count
  FROM target_patients tp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
    ON tp.subject_id = picd.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON picd.icd_code = dip.icd_code AND picd.icd_version = dip.icd_version
  WHERE dip.long_title LIKE '%catheter ablation%'
     OR dip.long_title LIKE '%cardioversion%'
  GROUP BY tp.subject_id
)
SELECT
  STDDEV(distinct_procedure_count) AS stddev_distinct_procedures_per_patient
FROM procedure_counts;
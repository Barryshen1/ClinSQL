WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
target_procedures AS (
  SELECT p.hadm_id,
         COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN target_patients tp
    ON p.subject_id = tp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(UPPER(d.long_title), r'CORONARY|ANGIOPLASTY|PCI')
  GROUP BY p.hadm_id
)
SELECT APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS percentile_75
FROM target_procedures;
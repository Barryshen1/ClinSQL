WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    (icd_version = 9 AND icd_code IN ('3610','3611','3612','3613','3614','3615','3616')) OR
    (icd_version = 10 AND icd_code IN ('0210','0211','0212','0213','0214','0215','0216','0217','0218','0219',
                                      '021A','021B','021C','021D','021E','021F','021G','021H','021W','021X','021Y','021Z'))
),
patient_procedure_counts AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS distinct_cabg_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN cabg_codes cc
    ON proc.icd_code = cc.icd_code AND proc.icd_version = cc.icd_version
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 45 AND 55
  GROUP BY p.subject_id
)
SELECT 
  PERCENTILE_CONT(distinct_cabg_count, 0.25) OVER() AS percentile_25
FROM patient_procedure_counts
LIMIT 1;
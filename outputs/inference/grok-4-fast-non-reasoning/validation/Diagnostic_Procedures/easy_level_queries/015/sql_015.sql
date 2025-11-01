WITH cabg_procedures AS (
  SELECT DISTINCT p.subject_id, p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE p.icd_version = 10
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      WHERE d.icd_code = p.icd_code
        AND d.icd_version = 10
        AND (LOWER(d.long_title) LIKE '%cabg%' OR LOWER(d.long_title) LIKE '%coronary artery bypass%')
    )
),
patient_cabg_counts AS (
  SELECT 
    pat.subject_id,
    COUNT(DISTINCT cabg.icd_code) AS distinct_cabg_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN cabg_procedures cabg 
    ON pat.subject_id = cabg.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
  GROUP BY pat.subject_id
  HAVING distinct_cabg_count > 0
)
SELECT 
  PERCENTILE_CONT(0.25, distinct_cabg_count) OVER() AS p25_distinct_cabg_per_patient
FROM patient_cabg_counts;
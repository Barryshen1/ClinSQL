WITH asthma_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(dicd.long_title) LIKE '%asthma%'
    AND a.dischtime IS NOT NULL
),
los_categories AS (
  SELECT 
    hadm_id,
    EXTRACT(DAY FROM (dischtime - admittime)) AS los_days
  FROM asthma_patients
),
procedure_counts AS (
  SELECT 
    lc.hadm_id,
    lc.los_days,
    COUNT(pi.seq_num) AS procedure_count
  FROM los_categories lc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON lc.hadm_id = pi.hadm_id
  WHERE lc.los_days BETWEEN 1 AND 7
  GROUP BY lc.hadm_id, lc.los_days
),
final_groups AS (
  SELECT 
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_category,
    procedure_count
  FROM procedure_counts
  WHERE los_days BETWEEN 1 AND 7
)
SELECT 
  los_category,
  PERCENTILE_CONT(procedure_count, 0.25) AS p25,
  PERCENTILE_CONT(procedure_count, 0.50) AS p50,
  PERCENTILE_CONT(procedure_count, 0.75) AS p75
FROM final_groups
WHERE los_category IS NOT NULL
GROUP BY los_category
ORDER BY los_category;
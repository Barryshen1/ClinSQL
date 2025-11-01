WITH pancreatitis_admissions AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    CASE 
      WHEN d.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_sequence
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%pancreatitis%'
),
admissions_with_los AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 52 AND 62
),
procedures_per_admission AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS procedure_count
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  GROUP BY p.hadm_id
),
final_admissions AS (
  SELECT 
    pa.hadm_id,
    pa.diagnosis_sequence,
    CASE 
      WHEN awl.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN awl.los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_group,
    COALESCE(ppa.procedure_count, 0) AS procedure_count
  FROM pancreatitis_admissions pa
  JOIN admissions_with_los awl
    ON pa.hadm_id = awl.hadm_id
  LEFT JOIN procedures_per_admission ppa
    ON pa.hadm_id = ppa.hadm_id
  WHERE awl.los_days BETWEEN 1 AND 8
)
SELECT 
  los_group,
  diagnosis_sequence,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM final_admissions
WHERE los_group IS NOT NULL
GROUP BY los_group, diagnosis_sequence
ORDER BY los_group, diagnosis_sequence;
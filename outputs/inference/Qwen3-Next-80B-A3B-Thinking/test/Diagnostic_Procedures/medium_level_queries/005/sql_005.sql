WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 49 AND 59
),
ischemic_stroke_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE WHEN MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN filtered_patients fp ON a.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.icd_code LIKE 'I63%' AND d.icd_version = 10
  GROUP BY a.hadm_id, a.admittime, a.dischtime
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_group,
  diagnosis_type,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM ischemic_stroke_admissions isa
JOIN procedure_counts pc ON isa.hadm_id = pc.hadm_id
WHERE los_days BETWEEN 1 AND 8
GROUP BY los_group, diagnosis_type;
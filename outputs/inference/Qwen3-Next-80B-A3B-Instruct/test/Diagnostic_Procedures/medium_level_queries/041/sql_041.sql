WITH patients_filtered AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
admissions_with_pancreatitis AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days,
    d.seq_num
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  INNER JOIN patients_filtered p
    ON a.subject_id = p.subject_id
  WHERE LOWER(di.long_title) LIKE '%acute pancreatitis%'
),
imaging_counts AS (
  SELECT 
    i.hadm_id,
    COUNT(*) AS imaging_count
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON c.stay_id = i.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%ct%'
     OR LOWER(d.label) LIKE '%radiograph%'
     OR LOWER(d.label) LIKE '%x-ray%'
     OR LOWER(d.label) LIKE '%radiography%'
     OR LOWER(d.label) LIKE '%imaging%'
     OR LOWER(d.label) LIKE '%scan%'
  GROUP BY i.hadm_id
),
final_data AS (
  SELECT 
    a.hadm_id,
    a.los_days,
    CASE 
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group,
    CASE 
      WHEN a.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM admissions_with_pancreatitis a
  LEFT JOIN imaging_counts i
    ON a.hadm_id = i.hadm_id
  WHERE a.los_days BETWEEN 1 AND 7
)
SELECT 
  los_group,
  diagnosis_type,
  COUNT(hadm_id) AS patient_count,
  AVG(imaging_count) AS mean_imaging_per_admission
FROM final_data
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;
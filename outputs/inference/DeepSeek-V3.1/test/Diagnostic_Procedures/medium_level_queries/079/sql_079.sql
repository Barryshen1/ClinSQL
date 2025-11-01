WITH lgib_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    d.seq_num,
    -- Categorize LOS
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_category,
    -- Flag primary vs secondary diagnosis
    CASE 
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5781', '5789')) OR
      (d.icd_version = 10 AND d.icd_code IN ('K625', 'K921', 'K922'))
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

radiology_procedures AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%ct%' OR
    LOWER(d.long_title) LIKE '%computed tomography%' OR
    LOWER(d.long_title) LIKE '%radiograph%' OR
    LOWER(d.long_title) LIKE '%x-ray%'
  GROUP BY hadm_id
)

SELECT 
  la.los_category,
  la.diagnosis_type,
  COUNT(DISTINCT la.hadm_id) AS num_admissions,
  COALESCE(SUM(rp.num_procedures), 0) AS total_procedures,
  COALESCE(SUM(rp.num_procedures), 0) / COUNT(DISTINCT la.hadm_id) AS mean_procedures_per_admission
FROM lgib_admissions la
LEFT JOIN radiology_procedures rp
  ON la.hadm_id = rp.hadm_id
GROUP BY la.los_category, la.diagnosis_type
ORDER BY la.los_category, la.diagnosis_type;
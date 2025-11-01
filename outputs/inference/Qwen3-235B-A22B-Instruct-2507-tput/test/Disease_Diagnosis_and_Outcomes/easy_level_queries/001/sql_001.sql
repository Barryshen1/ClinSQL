WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
ugib_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (
    (di.icd_version = 10 AND d.icd_code IN ('K920', 'K921', 'K922'))
    OR (di.icd_version = 9 AND d.icd_code LIKE '578%')
  )
),
copd_exac_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (
    (di.icd_version = 10 AND d.icd_code = 'J441')
    OR (di.icd_version = 9 AND d.icd_code IN ('49121', '496') AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di2
      JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d2
        ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
      WHERE di2.hadm_id = di.hadm_id
        AND d2.icd_version = 9
        AND d2.icd_code IN ('4660', '4661', '46619') -- acute bronchitis as proxy for exacerbation
    ))
  )
),
qualified_admissions AS (
  SELECT pa.hadm_id
  FROM patient_admissions pa
  INNER JOIN ugib_codes u ON pa.hadm_id = u.hadm_id
  INNER JOIN copd_exac_codes c ON pa.hadm_id = c.hadm_id
  WHERE pa.age_at_admission BETWEEN 86 AND 96
)
SELECT
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los_days
FROM qualified_admissions qa
JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON qa.hadm_id = a.hadm_id;
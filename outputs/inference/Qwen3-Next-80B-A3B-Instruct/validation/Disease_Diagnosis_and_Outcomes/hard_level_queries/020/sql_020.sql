WITH ami_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND (
      LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
      OR d.icd_code LIKE '410%'  -- ICD-9
      OR d.icd_code LIKE 'I21%'  -- ICD-10
    )
),
complications AS (
  SELECT
    d.hadm_id,
    COUNT(*) AS complication_count
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM ami_patients)
    AND (
      LOWER(dicd.long_title) LIKE '%cardiogenic shock%'
      OR LOWER(dicd.long_title) LIKE '%cardiac arrest%'
      OR LOWER(dicd.long_title) LIKE '%ventricular fibrillation%'
      OR LOWER(dicd.long_title) LIKE '%ventricular tachycardia%'
      OR LOWER(dicd.long_title) LIKE '%heart failure%'
      OR LOWER(dicd.long_title) LIKE '%acute kidney injury%'
      OR LOWER(dicd.long_title) LIKE '%respiratory failure%'
      OR LOWER(dicd.long_title) LIKE '%stroke%'
      OR LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%pulmonary embolism%'
    )
  GROUP BY d.hadm_id
),
risk_scores AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.anchor_age,
    ap.hospital_expire_flag,
    ap.admittime,
    ap.dischtime,
    COALESCE(c.complication_count, 0) AS complication_count,
    ap.anchor_age + COALESCE(c.complication_count, 0) AS risk_score
  FROM ami_patients ap
  LEFT JOIN complications c ON ap.hadm_id = c.hadm_id
),
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM risk_scores
)
SELECT DISTINCT
  risk_quintile,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(CASE WHEN complication_count > 0 THEN 1 ELSE 0 END) * 100 AS major_complication_pct,
  PERCENTILE_CONT(TIMESTAMP_DIFF(dischtime, admittime, DAY), 0.5) OVER (PARTITION BY risk_quintile) AS median_survivor_los_days
FROM quintiles
WHERE hospital_expire_flag = 0 OR hospital_expire_flag IS NOT NULL
ORDER BY risk_quintile;
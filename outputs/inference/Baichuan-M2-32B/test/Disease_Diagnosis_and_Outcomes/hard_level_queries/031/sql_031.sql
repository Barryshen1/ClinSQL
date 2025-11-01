WITH charlson_mapping AS (
  SELECT 'I21' AS icd_code, 1 AS weight, 'myocardial_infarction' AS category
  UNION ALL SELECT 'I50', 1, 'congestive_heart_failure'
  UNION ALL SELECT 'I70', 1, 'peripheral_vascular'
  UNION ALL SELECT 'I6', 1, 'cerebrovascular'
  UNION ALL SELECT 'F03', 1, 'dementia'
  UNION ALL SELECT 'M3', 1, 'rheumatologic'
  UNION ALL SELECT 'K25', 1, 'peptic_ulcer'
  UNION ALL SELECT 'K26', 1, 'peptic_ulcer'
  UNION ALL SELECT 'K70', 1, 'mild_liver'
  UNION ALL SELECT 'E11', 1, 'diabetes'
  UNION ALL SELECT 'E10', 2, 'diabetes'
  UNION ALL SELECT 'E12', 2, 'diabetes'
  UNION ALL SELECT 'G72', 2, 'hemiplegia_paraplegia'
  UNION ALL SELECT 'N17', 2, 'renal'
  UNION ALL SELECT 'N18', 2, 'renal'
  UNION ALL SELECT 'C', 2, 'malignancy'
  UNION ALL SELECT 'C7', 6, 'malignancy'
  UNION ALL SELECT 'K71', 3, 'moderate_severe_liver'
  UNION ALL SELECT 'K72', 3, 'moderate_severe_liver'
  UNION ALL SELECT 'B24', 6, 'aids'
),
eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 85 AND 95
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'J45.901%'
        AND d.icd_version = 10  -- Added to ensure ICD-10
    )
),
diagnoses_for_cohort AS (
  SELECT
    d.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN eligible_admissions e
    ON d.hadm_id = e.hadm_id
  WHERE d.icd_version = 10  -- Added to ensure ICD-10
),
charlson_scores AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    COALESCE(SUM(weight), 0) AS cci  -- Changed MAX_WEIGHT to weight
  FROM eligible_admissions e
  LEFT JOIN diagnoses_for_cohort d
    ON e.hadm_id = d.hadm_id
  LEFT JOIN charlson_mapping cm
    ON d.icd_code LIKE CONCAT(cm.icd_code, '%')
  GROUP BY e.subject_id, e.hadm_id
),
cci_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    cci,
    NTILE(4) OVER (ORDER BY cci) AS quartile
  FROM charlson_scores
),
complications AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    MAX(CASE WHEN cm.category IN ('myocardial_infarction', 'congestive_heart_failure', 'peripheral_vascular', 'cerebrovascular') THEN 1 ELSE 0 END) AS has_cardiovascular,
    MAX(CASE WHEN cm.category IN ('dementia', 'hemiplegia_paraplegia', 'cerebrovascular') THEN 1 ELSE 0 END) AS has_neurologic
  FROM eligible_admissions e
  LEFT JOIN diagnoses_for_cohort d
    ON e.hadm_id = d.hadm_id
  LEFT JOIN charlson_mapping cm
    ON d.icd_code LIKE CONCAT(cm.icd_code, '%')
  GROUP BY e.hadm_id, e.subject_id
)
SELECT
  q.quartile,
  COUNT(DISTINCT q.hadm_id) AS num_patients,
  ROUND(100 * AVG(e.hospital_expire_flag), 2) AS mortality_rate,
  ROUND(100 * AVG(c.has_cardiovascular), 2) AS cardiovascular_complication_rate,
  ROUND(100 * AVG(c.has_neurologic), 2) AS neurologic_complication_rate
FROM cci_quartiles q
INNER JOIN eligible_admissions e
  ON q.hadm_id = e.hadm_id AND q.subject_id = e.subject_id
INNER JOIN complications c
  ON q.hadm_id = c.hadm_id AND q.subject_id = c.subject_id
GROUP BY q.quartile
ORDER BY q.quartile;
WITH patients_with_comorbidities AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di1 ON a.hadm_id = di1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d1 ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di2 ON a.hadm_id = di2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d2 ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age + DATE_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR)) BETWEEN 86 AND 96
    AND (
      (d1.icd_version = 10 AND d1.icd_code LIKE 'E11%') OR
      (d1.icd_version = 9 AND d1.icd_code LIKE '250%')
    )
    AND (
      (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%') OR
      (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
    )
),
first_admission AS (
  SELECT subject_id, MIN(admittime) AS first_admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
  WHERE subject_id IN (SELECT subject_id FROM patients_with_comorbidities)
  GROUP BY subject_id
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN first_admission fa ON a.subject_id = fa.subject_id AND a.admittime = fa.first_admittime
),
drug_exposure AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    COALESCE(p.stoptime, LEAST(DATETIME_ADD(p.starttime, INTERVAL 24 HOUR), c.dischtime)) AS stoptime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) NOT LIKE '%insulin%' 
        AND (
          LOWER(p.drug) LIKE '%metformin%' OR
          LOWER(p.drug) LIKE '%glipizide%' OR
          LOWER(p.drug) LIKE '%glyburide%' OR
          LOWER(p.drug) LIKE '%glimepiride%' OR
          LOWER(p.drug) LIKE '%sitagliptin%' OR
          LOWER(p.drug) LIKE '%saxagliptin%' OR
          LOWER(p.drug) LIKE '%linagliptin%' OR
          LOWER(p.drug) LIKE '%alogliptin%' OR
          LOWER(p.drug) LIKE '%vildagliptin%' OR
          LOWER(p.drug) LIKE '%pioglitazone%' OR
          LOWER(p.drug) LIKE '%rosiglitazone%' OR
          LOWER(p.drug) LIKE '%repaglinide%' OR
          LOWER(p.drug) LIKE '%nateglinide%' OR
          LOWER(p.drug) LIKE '%acarbose%' OR
          LOWER(p.drug) LIKE '%miglitol%'
        ) THEN 'Oral Agents'
      ELSE NULL
    END AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p ON c.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
    AND (
      LOWER(p.drug) LIKE '%insulin%' OR
      LOWER(p.drug) LIKE '%metformin%' OR
      LOWER(p.drug) LIKE '%glipizide%' OR
      LOWER(p.drug) LIKE '%glyburide%' OR
      LOWER(p.drug) LIKE '%glimepiride%' OR
      LOWER(p.drug) LIKE '%sitagliptin%' OR
      LOWER(p.drug) LIKE '%saxagliptin%' OR
      LOWER(p.drug) LIKE '%linagliptin%' OR
      LOWER(p.drug) LIKE '%alogliptin%' OR
      LOWER(p.drug) LIKE '%vildagliptin%' OR
      LOWER(p.drug) LIKE '%pioglitazone%' OR
      LOWER(p.drug) LIKE '%rosiglitazone%' OR
      LOWER(p.drug) LIKE '%repaglinide%' OR
      LOWER(p.drug) LIKE '%nateglinide%' OR
      LOWER(p.drug) LIKE '%acarbose%' OR
      LOWER(p.drug) LIKE '%miglitol%'
    )
),
drug_timing AS (
  SELECT 
    subject_id,
    drug_class,
    -- Flag if used in early window: [admittime, admittime + 12h]
    MAX(CASE 
      WHEN starttime < DATETIME_ADD(admittime, INTERVAL 12 HOUR) 
       AND stoptime > admittime 
      THEN 1 ELSE 0 END) AS used_early,
    -- Flag if used in late window: [dischtime - 72h, dischtime]
    MAX(CASE 
      WHEN starttime < dischtime 
       AND stoptime > DATETIME_SUB(dischtime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 END) AS used_late
  FROM drug_exposure
  WHERE drug_class IS NOT NULL
  GROUP BY subject_id, drug_class
),
summary AS (
  SELECT
    drug_class,
    AVG(used_early) AS early_rate,
    AVG(used_late) AS late_rate,
    AVG(CASE WHEN used_early = 1 AND used_late = 1 THEN 1 ELSE 0 END) AS both_rate,
    AVG(CASE WHEN used_early = 1 AND used_late = 0 THEN 1 ELSE 0 END) AS early_only_rate,
    AVG(CASE WHEN used_early = 0 AND used_late = 1 THEN 1 ELSE 0 END) AS late_only_rate,
    AVG(CASE WHEN used_early = 0 AND used_late = 0 THEN 1 ELSE 0 END) AS neither_rate
  FROM drug_timing
  GROUP BY drug_class
)
SELECT
  drug_class AS class,
  ROUND(100 * early_rate, 2) AS early_rate,
  ROUND(100 * late_rate, 2) AS late_rate,
  ROUND(100 * both_rate, 2) AS both_rate,
  ROUND(100 * early_only_rate, 2) AS early_only_rate,
  ROUND(100 * late_only_rate, 2) AS late_only_rate,
  ROUND(100 * neither_rate, 2) AS neither_rate
FROM summary
ORDER BY drug_class;
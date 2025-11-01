WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    i.hadm_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND (
      d_icd.long_title LIKE '%Diabetes Mellitus%' 
      OR d.icd_code LIKE 'E1%'
    )
    AND (
      d_icd.long_title LIKE '%Heart Failure%' 
      OR d.icd_code LIKE 'I50%'
    )
    AND i.los >= 3  -- ICU stay at least 72 hours (3 days)
),

prescriptions_in_icu AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug,
    p.route,
    c.intime,
    c.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime IS NOT NULL
),

med_class AS (
  SELECT
    subject_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN drug IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 'rosiglitazone',
        'sitagliptin', 'saxagliptin', 'linagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin',
        'repaglinide', 'nateglinide', 'chlorpropamide', 'tolbutamide', 'acetohexamide', 'tolazamide'
      ) THEN 'Oral'
      ELSE 'Other'
    END AS drug_class
  FROM prescriptions_in_icu
),

patient_window_exposure AS (
  SELECT
    subject_id,
    MAX(CASE
      WHEN starttime BETWEEN intime AND intime + INTERVAL 12 HOUR
        AND drug_class = 'Insulin' THEN 1
      ELSE 0
    END) AS early_insulin,
    MAX(CASE
      WHEN starttime BETWEEN intime AND intime + INTERVAL 12 HOUR
        AND drug_class = 'Oral' THEN 1
      ELSE 0
    END) AS early_oral,
    MAX(CASE
      WHEN starttime BETWEEN outtime - INTERVAL 72 HOUR AND outtime
        AND drug_class = 'Insulin' THEN 1
      ELSE 0
    END) AS late_insulin,
    MAX(CASE
      WHEN starttime BETWEEN outtime - INTERVAL 72 HOUR AND outtime
        AND drug_class = 'Oral' THEN 1
      ELSE 0
    END) AS late_oral
  FROM med_class
  GROUP BY subject_id, intime, outtime
),

summary AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(early_insulin) AS early_insulin_count,
    SUM(early_oral) AS early_oral_count,
    SUM(late_insulin) AS late_insulin_count,
    SUM(late_oral) AS late_oral_count,
    SUM(CASE WHEN early_oral = 1 AND late_insulin = 1 THEN 1 ELSE 0 END) AS transition_oral_to_insulin,
    SUM(CASE WHEN early_insulin = 1 AND late_oral = 1 THEN 1 ELSE 0 END) AS transition_insulin_to_oral,
    SUM(CASE WHEN early_insulin = 1 AND late_insulin = 1 THEN 1 ELSE 0 END) AS transition_insulin_continued,
    SUM(CASE WHEN early_oral = 1 AND late_oral = 1 THEN 1 ELSE 0 END) AS transition_oral_continued
  FROM patient_window_exposure
)

SELECT
  ROUND(100.0 * early_insulin_count / total_patients, 2) AS early_insulin_rate_percent,
  ROUND(100.0 * early_oral_count / total_patients, 2) AS early_oral_rate_percent,
  ROUND(100.0 * late_insulin_count / total_patients, 2) AS late_insulin_rate_percent,
  ROUND(100.0 * late_oral_count / total_patients, 2) AS late_oral_rate_percent,
  transition_oral_to_insulin,
  transition_insulin_to_oral,
  transition_insulin_continued,
  transition_oral_continued
FROM summary;
WITH
-- Define our patient cohort: females 54-64 with diabetes and heart failure
patient_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE 'E11%' OR di.long_title LIKE '%diabetes%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE 'I50%' OR di.long_title LIKE '%heart failure%')
    )
),

-- Get all diabetes medications
diabetes_meds AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride',
        'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin',
        'linagliptin', 'alogliptin', 'repaglinide', 'nateglinide',
        'acarbose', 'miglitol', 'canagliflozin', 'dapagliflozin',
        'empagliflozin', 'ertugliflozin'
      ) THEN 'Oral Agent'
      ELSE NULL
    END AS medication_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%insulin%'
    OR LOWER(drug) IN (
      'metformin', 'glipizide', 'glyburide', 'glimepiride',
      'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin',
      'linagliptin', 'alogliptin', 'repaglinide', 'nateglinide',
      'acarbose', 'miglitol', 'canagliflozin', 'dapagliflozin',
      'empagliflozin', 'ertugliflozin'
    )
),

-- First 12 hours medication usage
first_12h_meds AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.medication_type) AS med_count
  FROM
    patient_cohort pc
  JOIN
    diabetes_meds dm
    ON pc.subject_id = dm.subject_id AND pc.hadm_id = dm.hadm_id
  WHERE
    dm.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 12 HOUR)
  GROUP BY
    pc.subject_id, pc.hadm_id, dm.medication_type
),

-- Final 48 hours medication usage
final_48h_meds AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.medication_type) AS med_count
  FROM
    patient_cohort pc
  JOIN
    diabetes_meds dm
    ON pc.subject_id = dm.subject_id AND pc.hadm_id = dm.hadm_id
  WHERE
    dm.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 48 HOUR) AND pc.dischtime
  GROUP BY
    pc.subject_id, pc.hadm_id, dm.medication_type
),

-- Count patients in each medication category for each time window
first_12h_counts AS (
  SELECT
    medication_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    first_12h_meds
  GROUP BY
    medication_type
),

final_48h_counts AS (
  SELECT
    medication_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    final_48h_meds
  GROUP BY
    medication_type
),

-- Total patients in cohort
total_patients AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total
  FROM
    patient_cohort
)

-- Final results with prevalence and net change
SELECT
  COALESCE(f12.medication_type, f48.medication_type) AS medication_type,
  COALESCE(f12.patient_count, 0) AS first_12h_patients,
  ROUND(COALESCE(f12.patient_count, 0) / t.total * 100, 2) AS first_12h_prevalence,
  COALESCE(f48.patient_count, 0) AS final_48h_patients,
  ROUND(COALESCE(f48.patient_count, 0) / t.total * 100, 2) AS final_48h_prevalence,
  ROUND((COALESCE(f48.patient_count, 0) - COALESCE(f12.patient_count, 0)) / t.total * 100, 2) AS net_change_pp
FROM
  first_12h_counts f12
FULL OUTER JOIN
  final_48h_counts f48
  ON f12.medication_type = f48.medication_type
CROSS JOIN
  total_patients t
ORDER BY
  medication_type;
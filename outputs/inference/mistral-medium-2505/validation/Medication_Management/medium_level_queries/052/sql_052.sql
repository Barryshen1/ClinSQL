WITH
-- Get qualifying patients (45-55yo males with T2DM and HF)
qualifying_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS stay_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hadm_id IN (
      -- Patients with type 2 diabetes (E11.x)
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'E11%'
    )
    AND a.hadm_id IN (
      -- Patients with heart failure (I50.x)
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%'
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
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
        'linagliptin', 'alogliptin', 'canagliflozin', 'dapagliflozin',
        'empagliflozin', 'ertugliflozin', 'acarbose', 'miglitol',
        'repaglinide', 'nateglinide'
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
      'linagliptin', 'alogliptin', 'canagliflozin', 'dapagliflozin',
      'empagliflozin', 'ertugliflozin', 'acarbose', 'miglitol',
      'repaglinide', 'nateglinide'
    )
),

-- First 48 hours medication usage
first_48h_meds AS (
  SELECT
    qp.subject_id,
    qp.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.medication_type) AS count
  FROM
    qualifying_patients qp
  JOIN
    diabetes_meds dm
    ON qp.subject_id = dm.subject_id AND qp.hadm_id = dm.hadm_id
  WHERE
    dm.starttime BETWEEN qp.admittime AND TIMESTAMP_ADD(qp.admittime, INTERVAL 48 HOUR)
  GROUP BY
    qp.subject_id, qp.hadm_id, dm.medication_type
),

-- Final 24 hours medication usage
final_24h_meds AS (
  SELECT
    qp.subject_id,
    qp.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.medication_type) AS count
  FROM
    qualifying_patients qp
  JOIN
    diabetes_meds dm
    ON qp.subject_id = dm.subject_id AND qp.hadm_id = dm.hadm_id
  WHERE
    dm.starttime BETWEEN TIMESTAMP_SUB(qp.dischtime, INTERVAL 24 HOUR) AND qp.dischtime
  GROUP BY
    qp.subject_id, qp.hadm_id, dm.medication_type
),

-- Count patients with each medication type in each time window
first_48h_counts AS (
  SELECT
    medication_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    first_48h_meds
  GROUP BY
    medication_type
),

final_24h_counts AS (
  SELECT
    medication_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    final_24h_meds
  GROUP BY
    medication_type
),

-- Total qualifying patients
total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total
  FROM qualifying_patients
)

-- Final results with percentages
SELECT
  'First 48 hours' AS time_window,
  f48.medication_type,
  f48.patient_count,
  ROUND((f48.patient_count / t.total) * 100, 2) AS percentage
FROM
  first_48h_counts f48
CROSS JOIN
  total_patients t
WHERE
  f48.medication_type IS NOT NULL

UNION ALL

SELECT
  'Final 24 hours' AS time_window,
  f24.medication_type,
  f24.patient_count,
  ROUND((f24.patient_count / t.total) * 100, 2) AS percentage
FROM
  final_24h_counts f24
CROSS JOIN
  total_patients t
WHERE
  f24.medication_type IS NOT NULL
ORDER BY
  time_window, medication_type;
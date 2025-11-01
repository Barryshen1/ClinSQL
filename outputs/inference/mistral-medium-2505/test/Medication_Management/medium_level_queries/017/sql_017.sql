WITH
-- Define age range and gender filter
female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 37 AND 47
),

-- Get qualifying ICU stays (>=144 hours)
qualifying_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
  WHERE
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) >= 144
),

-- Identify patients with diabetes and heart failure
diabetes_hf_patients AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.stay_id,
    q.icu_intime,
    q.icu_outtime
  FROM
    qualifying_stays q
  WHERE
    -- Diabetes ICD codes (E11, E13, etc.)
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = q.subject_id
        AND d.hadm_id = q.hadm_id
        AND (di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%')
    )
    -- Heart failure ICD codes (I50, etc.)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = q.subject_id
        AND d.hadm_id = q.hadm_id
        AND di.icd_code LIKE 'I50%'
    )
),

-- Get medication data for each patient with proper classification
medication_data AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    d.icu_intime,
    d.icu_outtime,
    p.drug,
    p.starttime,
    p.stoptime,
    CASE
      WHEN UPPER(p.drug) IN (
        'INSULIN', 'METFORMIN', 'GLIPIZIDE', 'GLYBURIDE', 'PIOGLITAZONE',
        'GLIMEPIRIDE', 'SITAGLIPTIN', 'LINAGLIPTIN', 'CANAGLIFLOZIN',
        'EMPAGLIFLOZIN', 'DAPAGLIFLOZIN', 'REPAGLINIDE', 'NATEGLINIDE'
      ) THEN 'Antidiabetic'
      WHEN UPPER(p.drug) IN (
        'METOPROLOL', 'CARVEDILOL', 'ATENOLOL', 'BISOPROLOL',
        'PROPRANOLOL', 'LABETALOL', 'NEBIVOLOL'
      ) THEN 'Beta-blocker'
      WHEN UPPER(p.drug) IN (
        'LISINOPRIL', 'LOSARTAN', 'VALSARTAN', 'SACUBITRIL/VALSARTAN',
        'ENALAPRIL', 'RAMIPRIL', 'CANDERSARTAN', 'OLMESARTAN',
        'IRBESARTAN', 'TELMISARTAN', 'CAPTOPRIL', 'QUINAPRIL'
      ) THEN 'ACEi/ARB/ARNI'
      WHEN UPPER(p.drug) IN (
        'FUROSEMIDE', 'BUMETANIDE', 'TORSEMIDE', 'ETHACRYNIC ACID'
      ) THEN 'Loop diuretic'
      ELSE NULL
    END AS medication_class
  FROM
    diabetes_hf_patients d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON d.subject_id = p.subject_id AND d.hadm_id = p.hadm_id
  WHERE
    p.drug IS NOT NULL
    AND CASE
      WHEN UPPER(p.drug) IN (
        'INSULIN', 'METFORMIN', 'GLIPIZIDE', 'GLYBURIDE', 'PIOGLITAZONE',
        'GLIMEPIRIDE', 'SITAGLIPTIN', 'LINAGLIPTIN', 'CANAGLIFLOZIN',
        'EMPAGLIFLOZIN', 'DAPAGLIFLOZIN', 'REPAGLINIDE', 'NATEGLINIDE',
        'METOPROLOL', 'CARVEDILOL', 'ATENOLOL', 'BISOPROLOL',
        'PROPRANOLOL', 'LABETALOL', 'NEBIVOLOL',
        'LISINOPRIL', 'LOSARTAN', 'VALSARTAN', 'SACUBITRIL/VALSARTAN',
        'ENALAPRIL', 'RAMIPRIL', 'CANDERSARTAN', 'OLMESARTAN',
        'IRBESARTAN', 'TELMISARTAN', 'CAPTOPRIL', 'QUINAPRIL',
        'FUROSEMIDE', 'BUMETANIDE', 'TORSEMIDE', 'ETHACRYNIC ACID'
      ) THEN TRUE
      ELSE FALSE
    END
),

-- Calculate medication usage in first 72h
first_72h_meds AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    medication_class,
    COUNT(DISTINCT drug) AS med_count
  FROM
    medication_data
  WHERE
    starttime <= TIMESTAMP_ADD(icu_intime, INTERVAL 72 HOUR)
    AND (stoptime IS NULL OR stoptime >= icu_intime)
  GROUP BY
    subject_id, hadm_id, stay_id, medication_class
),

-- Calculate medication usage in final 72h
final_72h_meds AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    medication_class,
    COUNT(DISTINCT drug) AS med_count
  FROM
    medication_data
  WHERE
    starttime <= icu_outtime
    AND (stoptime IS NULL OR stoptime >= TIMESTAMP_SUB(icu_outtime, INTERVAL 72 HOUR))
  GROUP BY
    subject_id, hadm_id, stay_id, medication_class
),

-- Count patients in each period
patient_counts AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients
  FROM
    diabetes_hf_patients
),

-- Get all possible medication classes for each patient
all_med_classes AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    stay_id,
    medication_class
  FROM
    medication_data
),

-- Calculate medication status changes
medication_changes AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.medication_class,
    CASE
      WHEN COALESCE(f.med_count, 0) > 0 AND COALESCE(l.med_count, 0) > 0 THEN 'Continued'
      WHEN COALESCE(f.med_count, 0) = 0 AND COALESCE(l.med_count, 0) > 0 THEN 'Initiated'
      WHEN COALESCE(f.med_count, 0) > 0 AND COALESCE(l.med_count, 0) = 0 THEN 'Discontinued'
      ELSE 'No change'
    END AS status_change
  FROM
    all_med_classes a
  LEFT JOIN
    first_72h_meds f ON a.subject_id = f.subject_id AND a.hadm_id = f.hadm_id
      AND a.stay_id = f.stay_id AND a.medication_class = f.medication_class
  LEFT JOIN
    final_72h_meds l ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
      AND a.stay_id = l.stay_id AND a.medication_class = l.medication_class
)

-- Final results
SELECT
  'First 72h' AS period,
  medication_class,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(COUNT(DISTINCT subject_id) * 100.0 / (SELECT total_patients FROM patient_counts), 2) AS percentage,
  NULL AS status_change,
  NULL AS count
FROM
  first_72h_meds
GROUP BY
  medication_class

UNION ALL

SELECT
  'Final 72h' AS period,
  medication_class,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(COUNT(DISTINCT subject_id) * 100.0 / (SELECT total_patients FROM patient_counts), 2) AS percentage,
  NULL AS status_change,
  NULL AS count
FROM
  final_72h_meds
GROUP BY
  medication_class

UNION ALL

SELECT
  'Status Changes' AS period,
  medication_class,
  NULL AS patient_count,
  NULL AS percentage,
  status_change,
  COUNT(*) AS count
FROM
  medication_changes
WHERE
  status_change IN ('Continued', 'Initiated', 'Discontinued')
GROUP BY
  medication_class, status_change

ORDER BY
  period, medication_class, status_change;
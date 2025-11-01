WITH
-- Get male patients aged 49-59
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 49 AND 59
),

-- Get admissions for these patients with T2DM and heart failure
t2dm_hf_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_patients mp ON a.subject_id = mp.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
      AND (d.long_title LIKE '%type 2 diabetes%' OR di.icd_code LIKE 'E11%')
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
      AND (d.long_title LIKE '%heart failure%' OR di.icd_code LIKE 'I50%')
  )
),

-- Get medication classes
medication_classes AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%'
        OR LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%sitagliptin%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%atenolol%' OR LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%bisoprolol%'
        OR LOWER(drug) LIKE '%propranolol%' THEN 'Beta-Blocker'
      WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%'
        OR LOWER(drug) LIKE '%sacubitril%' OR LOWER(drug) LIKE '%candesartan%' THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' OR LOWER(drug) LIKE '%torsemide%' THEN 'Loop Diuretic'
      ELSE NULL
    END AS medication_class,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- Get first 24h medications
first_24h_meds AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT mc.medication_class) AS count
  FROM medication_classes mc
  JOIN t2dm_hf_admissions a ON mc.subject_id = a.subject_id AND mc.hadm_id = a.hadm_id
  WHERE mc.starttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND (mc.stoptime IS NULL OR mc.stoptime >= a.admittime)
  GROUP BY mc.subject_id, mc.hadm_id, mc.medication_class
),

-- Get final 48h medications
final_48h_meds AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT mc.medication_class) AS count
  FROM medication_classes mc
  JOIN t2dm_hf_admissions a ON mc.subject_id = a.subject_id AND mc.hadm_id = a.hadm_id
  WHERE mc.starttime <= a.dischtime
    AND (mc.stoptime IS NULL OR mc.stoptime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR))
  GROUP BY mc.subject_id, mc.hadm_id, mc.medication_class
),

-- Get all medication classes for each patient
all_med_classes AS (
  SELECT
    subject_id,
    hadm_id,
    medication_class
  FROM medication_classes
  WHERE medication_class IS NOT NULL
  GROUP BY subject_id, hadm_id, medication_class
),

-- Determine medication status
medication_status AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    amc.medication_class,
    CASE
      WHEN f24.count IS NOT NULL AND f48.count IS NOT NULL THEN 'Continued'
      WHEN f24.count IS NULL AND f48.count IS NOT NULL THEN 'Initiated'
      WHEN f24.count IS NOT NULL AND f48.count IS NULL THEN 'Discontinued'
      ELSE NULL
    END AS status
  FROM t2dm_hf_admissions a
  CROSS JOIN (SELECT DISTINCT medication_class FROM medication_classes WHERE medication_class IS NOT NULL) amc
  LEFT JOIN first_24h_meds f24 ON a.subject_id = f24.subject_id AND a.hadm_id = f24.hadm_id AND amc.medication_class = f24.medication_class
  LEFT JOIN final_48h_meds f48 ON a.subject_id = f48.subject_id AND a.hadm_id = f48.hadm_id AND amc.medication_class = f48.medication_class
  WHERE amc.medication_class IS NOT NULL
),

-- Count patients by medication class and status
status_counts AS (
  SELECT
    medication_class,
    status,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM medication_status
  GROUP BY medication_class, status
),

-- Count total patients per medication class
total_patients AS (
  SELECT
    medication_class,
    COUNT(DISTINCT subject_id) AS total_patients
  FROM medication_status
  GROUP BY medication_class
)

-- Final result with percentages
SELECT
  mc.medication_class,
  SUM(CASE WHEN sc.status = 'Continued' THEN sc.patient_count ELSE 0 END) AS continued_count,
  SUM(CASE WHEN sc.status = 'Initiated' THEN sc.patient_count ELSE 0 END) AS initiated_count,
  SUM(CASE WHEN sc.status = 'Discontinued' THEN sc.patient_count ELSE 0 END) AS discontinued_count,
  SUM(sc.patient_count) AS total_on_medication,
  tp.total_patients,
  ROUND(SUM(sc.patient_count) / tp.total_patients * 100, 2) AS percent_on_medication
FROM (SELECT DISTINCT medication_class FROM medication_classes WHERE medication_class IS NOT NULL) mc
JOIN status_counts sc ON mc.medication_class = sc.medication_class
JOIN total_patients tp ON mc.medication_class = tp.medication_class
GROUP BY mc.medication_class, tp.total_patients
ORDER BY mc.medication_class;
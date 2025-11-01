WITH dka_admissions AS (
  -- Get admissions with DKA ICD codes
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    -- ICD-10 DKA codes
    (d.icd_version = 10 AND d.icd_code IN ('E101', 'E111', 'E131')) OR
    -- ICD-9 DKA codes (with or without dot)
    (d.icd_version = 9 AND (
      d.icd_code IN ('25010', '25011', '25012', '25013', '250.10', '250.11', '250.12', '250.13')
    ))
  )
),
female_patients AS (
  -- Get female patients
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
glucose_itemids AS (
  -- Get itemids for serum glucose
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%glucose%'
    AND LOWER(fluid) = 'blood'
),
peak_glucose_per_admission AS (
  -- For each DKA admission in a female patient, get peak glucose
  SELECT
    da.subject_id,
    da.hadm_id,
    MAX(le.valuenum) AS peak_glucose
  FROM dka_admissions da
  INNER JOIN female_patients fp ON da.subject_id = fp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON da.subject_id = le.subject_id AND da.hadm_id = le.hadm_id
  INNER JOIN glucose_itemids gi ON le.itemid = gi.itemid
  WHERE le.valuenum IS NOT NULL
  GROUP BY da.subject_id, da.hadm_id
)
-- Compute the median of peak glucose values
SELECT
  APPROX_QUANTILES(peak_glucose, 2)[OFFSET(1)] AS median_peak_serum_glucose
FROM peak_glucose_per_admission;
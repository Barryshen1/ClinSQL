WITH dka_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '2501%')  -- ICD-9 DKA codes (250.1x)
      OR 
      (d.icd_version = 10 AND d.icd_code IN ('E101', 'E111', 'E131', 'E141'))  -- ICD-10 DKA codes
    )
),
peak_glucose_per_admission AS (
  SELECT 
    l.hadm_id, 
    MAX(l.valuenum) AS peak_glucose
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN dka_admissions da
    ON l.hadm_id = da.hadm_id AND l.subject_id = da.subject_id
  WHERE 
    l.itemid = 50809  -- Serum glucose itemid
    AND l.valuenum IS NOT NULL  -- Ensure numeric value
  GROUP BY l.hadm_id
)
SELECT 
  APPROX_QUANTILES(peak_glucose, 2)[OFFSET(1)] AS median_peak_glucose
FROM peak_glucose_per_admission;
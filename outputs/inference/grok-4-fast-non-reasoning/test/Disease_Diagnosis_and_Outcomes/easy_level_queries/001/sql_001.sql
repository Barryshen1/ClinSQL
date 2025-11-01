WITH ugib_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = '10'
    AND icd_code IN ('I85.01', 'I85.11',  -- Esophageal varices with bleed
                     'K25.0', 'K25.4',    -- Duodenal ulcer with bleed/perforation
                     'K26.0', 'K26.4',    -- Gastric ulcer with bleed/perforation
                     'K22.11',             -- Esophagitis ulcer bleed
                     'K22.21', 'K22.22',   -- Ulcer of esophagus with bleed
                     'I85.21', 'I85.22',   -- Secondary esophageal varices bleed
                     'K92.0', 'K92.1')     -- Hematemesis/Melena (upper GI indicators)
),
copd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = '10'
    AND icd_code IN ('J44.0', 'J44.1', 'J44.9')  -- COPD with exacerbation/infection/unspecified
)
SELECT
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 86 AND 96
  AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0  -- Exclude invalid/zero LOS
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN ugib_codes u ON d.icd_code = u.icd_code
    WHERE d.subject_id = a.subject_id
      AND d.hadm_id = a.hadm_id
      AND d.icd_version = '10'
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    INNER JOIN copd_codes c ON d2.icd_code = c.icd_code
    WHERE d2.subject_id = a.subject_id
      AND d2.hadm_id = a.hadm_id
      AND d2.icd_version = '10'
  );
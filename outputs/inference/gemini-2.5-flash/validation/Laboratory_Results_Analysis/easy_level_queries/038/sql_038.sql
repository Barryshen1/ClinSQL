SELECT
  MIN(le.valuenum) AS min_hemoglobin_24hr_stroke_males
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON ad.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON ad.subject_id = le.subject_id AND ad.hadm_id = le.hadm_id
WHERE
  p.gender = 'M'
  -- Filter admissions for ischemic stroke diagnoses
  AND ad.hadm_id IN (
    SELECT DISTINCT
      diag.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    WHERE
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%') -- ICD-10 for Ischemic Stroke
      OR (diag.icd_version = 9 AND (diag.icd_code LIKE '433%1' OR diag.icd_code LIKE '434%')) -- ICD-9 for Ischemic Stroke
  )
  -- Filter for Hemoglobin lab tests (itemid 50810)
  AND le.itemid = 50810
  -- Ensure numeric value is present and valid
  AND le.valuenum IS NOT NULL
  AND le.valuenum > 0
  -- Filter lab events within 24 hours of admission
  AND le.charttime >= ad.admittime
  AND le.charttime <= DATETIME_ADD(ad.admittime, INTERVAL 24 HOUR);
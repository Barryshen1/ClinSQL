WITH
-- Get female patients aged 38-48
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
),

-- Get AKI admissions (using ICD-10 codes for AKI)
aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS stay_duration_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
         WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
         ELSE NULL END AS duration_category,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    ) THEN 'With ICU' ELSE 'Without ICU' END AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients p ON a.subject_id = p.subject_id
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
      WHERE
        d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE 'N17%' OR d.icd_code = 'R34' OR di.long_title LIKE '%acute kidney injury%')
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count non-invasive lab tests per admission
lab_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT d.itemid) AS non_invasive_diagnostics_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE
    -- Filter for non-invasive tests (excluding invasive procedures)
    d.category NOT IN ('Blood Gas', 'Hemodynamics', 'Cardiac')
    AND l.hadm_id IN (SELECT hadm_id FROM aki_admissions)
  GROUP BY
    hadm_id
)

-- Final aggregation
SELECT
  aa.duration_category,
  aa.icu_status,
  COUNT(DISTINCT aa.hadm_id) AS admission_count,
  AVG(lc.non_invasive_diagnostics_count) AS mean_diagnostics,
  MIN(lc.non_invasive_diagnostics_count) AS min_diagnostics,
  MAX(lc.non_invasive_diagnostics_count) AS max_diagnostics
FROM
  aki_admissions aa
LEFT JOIN
  lab_counts lc ON aa.hadm_id = lc.hadm_id
WHERE
  aa.duration_category IS NOT NULL
GROUP BY
  aa.duration_category,
  aa.icu_status
ORDER BY
  aa.duration_category,
  aa.icu_status;
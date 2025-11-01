WITH aki_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute kidney injury%'
),

-- Count non-invasive diagnostics per admission: lab + microbiology events
diag_counts AS (
  SELECT hadm_id,
         COUNT(*) AS diag_count
  FROM (
    SELECT hadm_id, charttime FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    UNION ALL
    SELECT hadm_id, charttime FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents`
  )
  GROUP BY hadm_id
)

SELECT
  CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_use,
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS stay_group,
  ROUND(AVG(dc.diag_count), 2)   AS mean_diag_per_admission,
  MIN(dc.diag_count)             AS min_diag_per_admission,
  MAX(dc.diag_count)             AS max_diag_per_admission
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN aki_admissions ak
    ON a.subject_id = ak.subject_id
   AND a.hadm_id   = ak.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
) AS base
LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON base.subject_id = icu.subject_id
 AND base.hadm_id    = icu.hadm_id
LEFT JOIN diag_counts dc
  ON base.hadm_id = dc.hadm_id
GROUP BY icu_use, stay_group
ORDER BY icu_use, stay_group;
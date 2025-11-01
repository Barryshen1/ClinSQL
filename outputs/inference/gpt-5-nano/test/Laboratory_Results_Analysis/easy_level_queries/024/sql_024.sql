WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  WHERE (LOWER(dd.long_title) LIKE '%sepsis%' OR LOWER(dd.long_title) LIKE '%septic%')
    AND pat.gender = 'M'
),

-- 2) For those admissions, get the earliest platelet count during the admission
platelet_per_admission AS (
  SELECT
      le.hadm_id,
      le.valuenum AS platelet_valuenum,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON le.hadm_id = a.hadm_id
  WHERE le.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND LOWER(dli.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN a.admittime AND a.dischtime
)

SELECT
  STDDEV_SAMP(platelet_valuenum) AS platelet_count_sd
FROM platelet_per_admission
WHERE rn = 1;
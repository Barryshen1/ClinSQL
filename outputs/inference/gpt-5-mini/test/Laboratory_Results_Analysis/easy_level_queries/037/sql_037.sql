WITH sepsis_adms AS (
  -- admissions with a sepsis diagnosis (any ICD version)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%sepsis%'
     OR LOWER(dicd.long_title) LIKE '%septic%'
),

male_sepsis_adms AS (
  -- restrict to male patients
  SELECT sa.subject_id, sa.hadm_id
  FROM sepsis_adms sa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON sa.subject_id = p.subject_id
  WHERE p.gender = 'M'
),

platelet_labs AS (
  -- platelet lab measurements for those male sepsis admissions
  SELECT le.subject_id,
         le.hadm_id,
         le.charttime,
         le.valuenum,
         li.label AS lab_label,
         le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  JOIN male_sepsis_adms msa
    ON le.subject_id = msa.subject_id
   AND le.hadm_id = msa.hadm_id
  WHERE LOWER(li.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
),

subject_peak AS (
  -- peak platelet per subject (across their sepsis admissions)
  SELECT subject_id,
         MAX(valuenum) AS peak_platelet
  FROM platelet_labs
  GROUP BY subject_id
)

-- 75th percentile of per-subject peak platelet counts
SELECT
  APPROX_QUANTILES(peak_platelet, 100)[OFFSET(75)] AS p75_peak_platelet_count
FROM subject_peak;
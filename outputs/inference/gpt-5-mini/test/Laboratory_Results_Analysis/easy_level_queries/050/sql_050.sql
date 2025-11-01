WITH sepsis_adms AS (
  -- admissions with any diagnosis whose long_title mentions "sepsis"
  -- only hadm_id is needed to avoid duplicate subject_id columns in later joins
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code
   AND d.icd_version = diag.icd_version
  WHERE LOWER(diag.long_title) LIKE '%sepsis%'
),

male_sepsis_adms AS (
  -- restrict to male patients and keep admittime for time-windowing labs
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN sepsis_adms s USING (hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING (subject_id)
  WHERE p.gender = 'M'
),

platelet_labs_first_24h AS (
  -- get platelet labs within 24 hours of admission; pick the earliest per admission
  SELECT
    ms.subject_id,
    ms.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY ms.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM male_sepsis_adms ms
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = ms.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= ms.admittime
    AND le.charttime <= TIMESTAMP_ADD(ms.admittime, INTERVAL 24 HOUR)
)

SELECT
  COUNT(1) AS n_admissions_with_platelet,
  STDDEV_SAMP(valuenum) AS platelet_count_sd
FROM platelet_labs_first_24h
WHERE rn = 1;
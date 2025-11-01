WITH septic_male_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dx
    ON dx.icd_code = di.icd_code AND dx.icd_version = di.icd_version
  WHERE (LOWER(dx.long_title) LIKE '%sepsis%' OR LOWER(dx.long_title) LIKE '%septicemia%')
    AND p.gender IN ('M', 'm', 'Male', 'MALE')
),
platelets_per_admission AS (
  SELECT
    sma.hadm_id,
    le.valuenum AS platelet_value,
    le.charttime
  FROM septic_male_admissions AS sma
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = sma.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = sma.hadm_id AND le.subject_id = sma.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%platelet%'
    AND le.charttime BETWEEN a.admittime AND a.dischtime
),
earliest_per_admission AS (
  SELECT
    hadm_id,
    platelet_value
  FROM (
    SELECT
      hadm_id,
      platelet_value,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM platelets_per_admission
  )
  WHERE rn = 1
)
SELECT STDDEV_SAMP(platelet_value) AS admission_platelet_count_sd
FROM earliest_per_admission
WHERE platelet_value IS NOT NULL;
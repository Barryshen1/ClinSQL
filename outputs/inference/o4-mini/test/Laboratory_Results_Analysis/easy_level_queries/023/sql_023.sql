WITH sepsis_admissions AS (
  -- Find all hospital admissions with a sepsis diagnosis
  SELECT DISTINCT d.subject_id,
                  d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
male_sepsis_admissions AS (
  -- Restrict to male patients
  SELECT sa.subject_id,
         sa.hadm_id,
         a.dischtime
  FROM sepsis_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON sa.subject_id = a.subject_id
   AND sa.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON sa.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
lactate_events AS (
  -- Extract serum lactate measurements on discharge day
  SELECT le.subject_id,
         le.hadm_id,
         le.valuenum AS lactate,
         DATE(le.charttime) AS lab_date,
         DATE(msa.dischtime) AS discharge_date
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  JOIN male_sepsis_admissions msa
    ON le.subject_id = msa.subject_id
   AND le.hadm_id = msa.hadm_id
  WHERE LOWER(li.label) LIKE '%lactate%'
    AND li.fluid = 'Blood'
    AND le.valuenum IS NOT NULL
    -- Ensure the lab was drawn on the discharge day
    AND DATE(le.charttime) = DATE(msa.dischtime)
)
-- Compute the 25th and 75th percentiles (IQR bounds)
SELECT
  quants[OFFSET(25)] AS p25_lactate,
  quants[OFFSET(75)] AS p75_lactate,
  quants[OFFSET(75)] - quants[OFFSET(25)] AS iqr_lactate
FROM (
  SELECT
    APPROX_QUANTILES(lactate, 100) AS quants
  FROM lactate_events
);
WITH target_patients AS (
  -- First, create the cohort of 90-year-old male patients with a COPD diagnosis.
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON p.subject_id = dx.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 90
    AND REGEXP_CONTAINS(LOWER(d.long_title), 'chronic obstructive pulmonary disease')
  GROUP BY p.subject_id
),
avg_creatinine_per_stay AS (
  -- Next, for each ICU stay of these patients, calculate the average creatinine
  -- in the first 24 hours.
  SELECT
    icu.stay_id,
    AVG(le.valuenum) AS avg_creatinine
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON icu.hadm_id = le.hadm_id
  WHERE
    -- Filter for the patient cohort identified above
    icu.subject_id IN (SELECT subject_id FROM target_patients)
    -- Filter for serum creatinine (itemid 50912)
    AND le.itemid = 50912
    AND le.valuenum IS NOT NULL
    -- Filter for measurements within the first 24 hours of the ICU stay
    AND le.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    icu.stay_id
)
-- Finally, calculate the standard deviation of these per-stay average creatinine values.
SELECT
  STDDEV(avg_creatinine) AS stddev_of_average_creatinine
FROM avg_creatinine_per_stay;
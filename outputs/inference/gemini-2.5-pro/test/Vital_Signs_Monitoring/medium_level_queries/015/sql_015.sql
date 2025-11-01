WITH cohort_stays AS (
  -- Step 1: Identify the ICU stays for the specific patient cohort.
  -- Cohort: Female patients, aged 59-69, admitted via the ED.
  SELECT
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND adm.admission_location = 'EMERGENCY ROOM'
    -- Calculate a more precise age at admission and filter
    AND (DATETIME_DIFF(adm.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 59 AND 69
), max_sbp_per_stay AS (
  -- Step 2: For each stay in the cohort, find the maximum systolic blood pressure.
  SELECT
    cs.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM cohort_stays AS cs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (
      220050, -- Arterial Blood Pressure systolic
      220179, -- Non Invasive Blood Pressure systolic
      225309, -- ART BP Systolic
      224167  -- Manual Blood Pressure SBP
    )
    -- Add a plausibility filter for SBP values
    AND ce.valuenum > 0 AND ce.valuenum < 300
  GROUP BY
    cs.stay_id
)
-- Step 3: Calculate the 75th percentile of the maximum SBP values across all selected stays.
SELECT
  APPROX_QUANTILES(max_sbp, 4)[OFFSET(3)] AS sbp_75th_percentile
FROM max_sbp_per_stay;
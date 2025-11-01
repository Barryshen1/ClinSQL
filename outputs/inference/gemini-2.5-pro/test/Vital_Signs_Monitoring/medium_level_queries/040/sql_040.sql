WITH cohort_stays AS (
  -- Step 1: Identify ICU stays for female patients aged 81-91 who received High-Flow Nasal Cannula (HFNC).
  SELECT DISTINCT
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pat.subject_id = icu.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON icu.stay_id = pe.stay_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND pe.itemid = 227287 -- itemid for 'High Flow Nasal Cannula'
),
mean_sbp_per_stay AS (
  -- Step 2: Calculate the mean systolic blood pressure (SBP) for each stay identified above.
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  WHERE
    ce.stay_id IN (SELECT stay_id FROM cohort_stays)
    AND ce.itemid IN (
      220050, -- Arterial Blood Pressure systolic
      220179, -- Non Invasive Blood Pressure systolic
      224643  -- Manual Blood Pressure SBP
    )
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- Basic data quality check for valid BP readings
  GROUP BY
    ce.stay_id
)
-- Step 3: Find the minimum of all the per-stay mean SBP values.
SELECT
  MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM mean_sbp_per_stay;
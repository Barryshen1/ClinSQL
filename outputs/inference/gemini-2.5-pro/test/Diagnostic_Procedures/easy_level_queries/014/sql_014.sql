WITH
-- Step 1: Identify the target patient population (males, aged 73-83)
target_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

-- Step 2: Get all hospitalizations for the target patient cohort
target_admissions AS (
  SELECT
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    target_patients AS pat
    ON adm.subject_id = pat.subject_id
),

-- Step 3: Identify events corresponding to mechanical circulatory support devices
mcs_events AS (
  SELECT
    proc.hadm_id,
    proc.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS proc
  WHERE
    proc.itemid IN (
      -- The following itemids represent various mechanical circulatory support devices
      224641, -- Intra-aortic balloon pump
      228373, -- Impella
      225450, -- VA-ECMO
      225449, -- VV-ECMO
      225442, -- CentriMag - R
      225443, -- CentriMag - L
      225444, -- Tandem Heart - L
      225445  -- Tandem Heart - R
    )
),

-- Step 4: Count the number of distinct MCS devices for each hospitalization in the target cohort
device_counts_per_hadm AS (
  SELECT
    ta.hadm_id,
    COUNT(DISTINCT mcs.itemid) AS num_distinct_devices
  FROM
    target_admissions AS ta
  LEFT JOIN -- Use LEFT JOIN to include hospitalizations with zero MCS devices
    mcs_events AS mcs
    ON ta.hadm_id = mcs.hadm_id
  GROUP BY
    ta.hadm_id
)

-- Step 5: Calculate the median number of distinct devices across all relevant hospitalizations
SELECT
  APPROX_QUANTILES(num_distinct_devices, 2)[OFFSET(1)] AS median_num_distinct_mcs_devices
FROM
  device_counts_per_hadm;
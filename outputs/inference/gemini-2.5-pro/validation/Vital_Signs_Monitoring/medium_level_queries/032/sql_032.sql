WITH cohort_stays AS (
  SELECT DISTINCT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    -- Condition 1: Female patients aged 53-63
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    -- Condition 2: Admitted to a step-down or IMC unit during the hospital stay
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.transfers` AS t
      WHERE
        t.hadm_id = adm.hadm_id
        AND (
          LOWER(t.careunit) LIKE '%stepdown%' OR LOWER(t.careunit) LIKE '%intermediate%'
        )
    )
    -- Condition 3: Received invasive mechanical ventilation during an ICU stay
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      WHERE
        pe.stay_id = icu.stay_id
        AND pe.itemid = 225792 -- Invasive Ventilation
    )
)
SELECT
  STDDEV(ce.valuenum) AS sbp_stddev_nighttime
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
WHERE
  -- Filter for SBP measurements (both invasive and non-invasive)
  ce.itemid IN (
    220050, -- Arterial Blood Pressure systolic
    220179 -- Non Invasive Blood Pressure systolic
  )
  -- Filter for the patient cohort identified in the CTE
  AND ce.stay_id IN (
    SELECT
      stay_id
    FROM
      cohort_stays
  )
  -- Filter for the nighttime window (00:00 to 06:00 inclusive)
  AND TIME(ce.charttime) BETWEEN TIME(0, 0, 0) AND TIME(6, 0, 0)
  -- Ensure the value is a valid number in mmHg
  AND ce.valueuom = 'mmHg'
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0 AND ce.valuenum < 400; -- Basic data cleaning for plausible values;
WITH
  -- Step 1: Identify hospital admissions for female patients aged 44-54.
  patient_cohort AS (
    SELECT
      adm.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND (
        pat.anchor_age + EXTRACT(
          YEAR
          FROM
            adm.admittime
        ) - pat.anchor_year
      ) BETWEEN 44 AND 54
  ),
  -- Step 2: Identify all prescriptions for relevant antiplatelet drugs and classify them.
  antiplatelet_scripts AS (
    SELECT
      hadm_id,
      starttime,
      stoptime,
      CASE
        WHEN LOWER(drug) LIKE '%aspirin%'
        THEN 'aspirin'
        WHEN
          LOWER(drug) LIKE '%clopidogrel%'
          OR LOWER(drug) LIKE '%plavix%'
          OR LOWER(drug) LIKE '%prasugrel%'
          OR LOWER(drug) LIKE '%effient%'
          OR LOWER(drug) LIKE '%ticagrelor%'
          OR LOWER(drug) LIKE '%brilinta%'
        THEN 'p2y12_inhibitor'
        ELSE NULL
      END AS drug_class
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      -- Broad filter for performance before the CASE statement
      LOWER(drug) LIKE '%aspirin%'
      OR LOWER(drug) LIKE '%clopidogrel%'
      OR LOWER(drug) LIKE '%plavix%'
      OR LOWER(drug) LIKE '%prasugrel%'
      OR LOWER(drug) LIKE '%effient%'
      OR LOWER(drug) LIKE '%ticagrelor%'
      OR LOWER(drug) LIKE '%brilinta%'
  ),
  -- Step 3: Identify the hospital admissions from our cohort that received DAPT.
  -- DAPT is defined as receiving at least one aspirin and one P2Y12 inhibitor during the admission.
  dapt_admissions AS (
    SELECT
      aps.hadm_id
    FROM
      antiplatelet_scripts AS aps
    WHERE
      aps.hadm_id IN (
        SELECT
          hadm_id
        FROM
          patient_cohort
      )
      AND aps.drug_class IS NOT NULL
    GROUP BY
      aps.hadm_id
    HAVING
      COUNT(DISTINCT aps.drug_class) >= 2
  )
-- Step 4: From the DAPT admissions, calculate the standard deviation of the duration 
-- of all single antiplatelet prescriptions.
SELECT
  STDDEV(
    DATETIME_DIFF(aps.stoptime, aps.starttime, DAY)
  ) AS sd_single_antiplatelet_duration_days
FROM
  antiplatelet_scripts AS aps
  INNER JOIN
    dapt_admissions AS da
    ON aps.hadm_id = da.hadm_id
WHERE
  -- Ensure duration is calculable and makes sense (is positive)
  aps.starttime IS NOT NULL
  AND aps.stoptime IS NOT NULL
  AND aps.stoptime > aps.starttime;
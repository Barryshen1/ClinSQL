WITH
  -- Step 1: Identify male patients in the specified age range
  cohort_patients AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 48 AND 58
  ),
  -- Step 2: Identify hospital admissions with diagnoses for both Type 2 Diabetes and Heart Failure
  diagnoses_by_hadm AS (
    SELECT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
    HAVING
      -- Flag for Type 2 Diabetes
      MAX(
        CASE
          WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E11' THEN 1
          WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250' THEN 1
          ELSE 0
        END
      ) = 1
      AND -- Flag for Heart Failure
      MAX(
        CASE
          WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50' THEN 1
          WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428' THEN 1
          ELSE 0
        END
      ) = 1
  ),
  -- Step 3: Combine patient demographics and diagnoses to form the final cohort of hospital admissions.
  -- Also, define the first and final 12-hour windows for each admission.
  cohort AS (
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      TIMESTAMP_ADD(adm.admittime, INTERVAL 12 HOUR) AS first_12h_end,
      TIMESTAMP_SUB(adm.dischtime, INTERVAL 12 HOUR) AS final_12h_start
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN cohort_patients AS cp ON adm.subject_id = cp.subject_id
      INNER JOIN diagnoses_by_hadm AS dx ON adm.hadm_id = dx.hadm_id
    WHERE
      -- Filter for stays >= 24 hours to ensure time windows are distinct
      TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) >= 24
  ),
  -- Step 4: Identify all administrations of GLP-1 receptor agonists from the emar table.
  -- "emar" is chosen as it records actual administration ("received") rather than just orders.
  glp1_administrations AS (
    SELECT
      hadm_id,
      charttime
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar`
    WHERE
      -- A comprehensive list of generic and brand names for GLP-1 receptor agonists
      LOWER(medication) LIKE '%semaglutide%'
      OR LOWER(medication) LIKE '%ozempic%'
      OR LOWER(medication) LIKE '%rybelsus%'
      OR LOWER(medication) LIKE '%wegovy%'
      OR LOWER(medication) LIKE '%liraglutide%'
      OR LOWER(medication) LIKE '%victoza%'
      OR LOWER(medication) LIKE '%saxenda%'
      OR LOWER(medication) LIKE '%dulaglutide%'
      OR LOWER(medication) LIKE '%trulicity%'
      OR LOWER(medication) LIKE '%exenatide%'
      OR LOWER(medication) LIKE '%byetta%'
      OR LOWER(medication) LIKE '%bydureon%'
      OR LOWER(medication) LIKE '%lixisenatide%'
      OR LOWER(medication) LIKE '%adlyxin%'
  ),
  -- Step 5: For each admission in the cohort, flag if a GLP-1 was administered in the first or final 12 hours.
  administration_flags AS (
    SELECT
      c.hadm_id,
      -- Flag is 1 if at least one administration occurred in the first 12 hours
      MAX(
        CASE
          WHEN g.charttime >= c.admittime AND g.charttime < c.first_12h_end THEN 1
          ELSE 0
        END
      ) AS received_in_first_12h,
      -- Flag is 1 if at least one administration occurred in the final 12 hours
      MAX(
        CASE
          WHEN g.charttime >= c.final_12h_start AND g.charttime <= c.dischtime THEN 1
          ELSE 0
        END
      ) AS received_in_final_12h
    FROM
      cohort AS c
      LEFT JOIN glp1_administrations AS g ON c.hadm_id = g.hadm_id
    GROUP BY
      c.hadm_id
  )
-- Step 6: Calculate the final metrics: total patients, percentages for each window, and the net change.
SELECT
  COUNT(hadm_id) AS total_cohort_admissions,
  -- First 12h Metrics
  SUM(received_in_first_12h) AS count_received_first_12h,
  SAFE_DIVIDE(SUM(received_in_first_12h) * 100.0, COUNT(hadm_id)) AS percent_received_first_12h,
  -- Final 12h Metrics
  SUM(received_in_final_12h) AS count_received_final_12h,
  SAFE_DIVIDE(SUM(received_in_final_12h) * 100.0, COUNT(hadm_id)) AS percent_received_final_12h,
  -- Net Change Calculation
  (
    SAFE_DIVIDE(SUM(received_in_final_12h) * 100.0, COUNT(hadm_id))
  ) - (
    SAFE_DIVIDE(SUM(received_in_first_12h) * 100.0, COUNT(hadm_id))
  ) AS net_change_percent
FROM
  administration_flags;
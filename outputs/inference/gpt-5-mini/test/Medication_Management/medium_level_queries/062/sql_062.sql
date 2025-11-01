WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    -- require a recorded discharge time so we can compute final 72h window
    AND a.dischtime IS NOT NULL
    -- must have diabetes diagnosis in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING(icd_code, icd_version)
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- must have heart failure diagnosis in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING(icd_code, icd_version)
      WHERE di.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%heart failure%'
          OR LOWER(dd.long_title) LIKE '%congestive heart failure%'
        )
    )
),
glp_events_raw AS (
  -- prescriptions table
  SELECT
    hadm_id,
    starttime AS event_time,
    LOWER(COALESCE(drug, '')) AS med,
    LOWER(COALESCE(route, '')) AS route
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL

  UNION ALL

  -- pharmacy dispensing/orders table
  SELECT
    hadm_id,
    starttime AS event_time,
    LOWER(COALESCE(medication, '')) AS med,
    LOWER(COALESCE(route, '')) AS route
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL

  UNION ALL

  -- emar (medication administration/record)
  SELECT
    hadm_id,
    charttime AS event_time,
    LOWER(COALESCE(medication, '')) AS med,
    '' AS route
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE charttime IS NOT NULL
),
glp_events AS (
  -- filter to likely GLP-1 injectables by generic or common brand names.
  -- Note: 'rybelsus' (oral semaglutide) purposely excluded.
  SELECT
    hadm_id,
    event_time
  FROM glp_events_raw
  WHERE
    (
      -- generics
      med LIKE '%liraglutide%'
      OR med LIKE '%exenatide%'
      OR med LIKE '%dulaglutide%'
      OR med LIKE '%semaglutide%'
      OR med LIKE '%albiglutide%'
      OR med LIKE '%lixisenatide%'
      OR med LIKE '%tirzepatide%'
      -- common brands (injectable)
      OR med LIKE '%victoza%'      -- liraglutide
      OR med LIKE '%byetta%'       -- exenatide
      OR med LIKE '%bydureon%'     -- exenatide extended
      OR med LIKE '%trulicity%'    -- dulaglutide
      OR med LIKE '%ozempic%'      -- semaglutide (injectable)
      OR med LIKE '%saxenda%'      -- liraglutide (weight loss formulation, injectable)
      OR med LIKE '%tanzeum%'      -- albiglutide (historical/brand)
      OR med LIKE '%adlyxin%'
    )
    -- Optionally, to be stricter about injectables, one could require route LIKE '%subcut%' OR route LIKE '%inject%'
    -- but route entries are often missing; adjust as needed.
),
glp_events_in_stay AS (
  -- keep only events that occur during the admission window
  SELECT
    g.hadm_id,
    g.event_time
  FROM glp_events g
  JOIN cohort c USING (hadm_id)
  WHERE g.event_time BETWEEN c.admittime AND c.dischtime
),
per_admission_flags AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- flag if at least one GLP-1 event in first 72 hours after admit
    MAX(CASE WHEN ge.event_time <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS any_first_72h,
    -- flag if at least one GLP-1 event in final 72 hours before discharge
    MAX(CASE WHEN ge.event_time >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS any_final_72h
  FROM cohort c
  LEFT JOIN glp_events_in_stay ge
    ON c.hadm_id = ge.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
)
SELECT
  COUNT(1) AS cohort_n,
  SUM(any_first_72h) AS n_first_72h,
  SUM(any_final_72h) AS n_final_72h,
  SAFE_DIVIDE(SUM(any_first_72h), COUNT(1)) AS rate_first_72h,
  SAFE_DIVIDE(SUM(any_final_72h), COUNT(1)) AS rate_final_72h,
  SAFE_DIVIDE(SUM(any_final_72h), COUNT(1)) - SAFE_DIVIDE(SUM(any_first_72h), COUNT(1)) AS absolute_change,
  CASE
    WHEN SAFE_DIVIDE(SUM(any_first_72h), COUNT(1)) > 0
    THEN (SAFE_DIVIDE(SUM(any_final_72h), COUNT(1)) - SAFE_DIVIDE(SUM(any_first_72h), COUNT(1)))
         / SAFE_DIVIDE(SUM(any_first_72h), COUNT(1))
    ELSE NULL
  END AS relative_change
FROM per_admission_flags;
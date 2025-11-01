WITH
-- Step 1: Base cohort: male patients age 48-58 and their admissions
base_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admittime IS NOT NULL
    AND a.hadm_id IS NOT NULL
),

-- Step 2: Summarize diagnoses per admission to detect T2D and heart failure
hadm_diagnoses AS (
  SELECT
    di.hadm_id,
    MAX(
      CASE
        WHEN lower(d.long_title) LIKE '%type 2%' THEN 1
        WHEN lower(d.long_title) LIKE '%type ii%' THEN 1
        WHEN lower(d.long_title) LIKE '%non-insulin-dependent%' THEN 1
        WHEN lower(d.long_title) LIKE '%diabetes%' AND NOT (lower(d.long_title) LIKE '%type 1%' OR lower(d.long_title) LIKE '%type i%' OR lower(d.long_title) LIKE '%insulin-dependent%') THEN 1
        ELSE 0
      END
    ) AS has_t2d_like,
    MAX(
      CASE
        WHEN lower(d.long_title) LIKE '%heart failure%' THEN 1
        ELSE 0
      END
    ) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY di.hadm_id
),

-- Step 3: Admissions that meet both clinical conditions (T2D-like AND heart failure)
cohort AS (
  SELECT
    ba.subject_id,
    ba.hadm_id,
    ba.admittime,
    ba.dischtime
  FROM base_admissions ba
  JOIN hadm_diagnoses hd
    ON ba.hadm_id = hd.hadm_id
  WHERE hd.has_hf = 1
    AND hd.has_t2d_like = 1
    -- ensure discharge time exists for final-12h window calculation
    AND ba.dischtime IS NOT NULL
),

-- Step 4: Gather medication/administration timestamps that match GLP-1 receptor agonists
med_admins AS (
  -- prescriptions
  SELECT
    hadm_id,
    starttime AS medtime,
    'prescriptions' AS source,
    drug AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL
    AND (
      lower(drug) LIKE '%liraglutide%' OR
      lower(drug) LIKE '%semaglutide%' OR
      lower(drug) LIKE '%dulaglutide%' OR
      lower(drug) LIKE '%exenatide%' OR
      lower(drug) LIKE '%lixisenatide%' OR
      lower(drug) LIKE '%albiglutide%' OR
      lower(drug) LIKE '%tirzepatide%'
    )

  UNION ALL

  -- pharmacy dispensation records
  SELECT
    hadm_id,
    starttime AS medtime,
    'pharmacy' AS source,
    medication AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL
    AND (
      lower(medication) LIKE '%liraglutide%' OR
      lower(medication) LIKE '%semaglutide%' OR
      lower(medication) LIKE '%dulaglutide%' OR
      lower(medication) LIKE '%exenatide%' OR
      lower(medication) LIKE '%lixisenatide%' OR
      lower(medication) LIKE '%albiglutide%' OR
      lower(medication) LIKE '%tirzepatide%'
    )

  UNION ALL

  -- emar medication charting (emar.charttime)
  SELECT
    hadm_id,
    charttime AS medtime,
    'emar' AS source,
    medication AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE charttime IS NOT NULL
    AND (
      lower(medication) LIKE '%liraglutide%' OR
      lower(medication) LIKE '%semaglutide%' OR
      lower(medication) LIKE '%dulaglutide%' OR
      lower(medication) LIKE '%exenatide%' OR
      lower(medication) LIKE '%lixisenatide%' OR
      lower(medication) LIKE '%albiglutide%' OR
      lower(medication) LIKE '%tirzepatide%'
    )

  UNION ALL

  -- ICU inputevents by joining to d_items labels (some ICU meds recorded by itemid)
  SELECT
    ie.hadm_id,
    ie.starttime AS medtime,
    'icu_inputevents' AS source,
    di.label AS med_text
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime IS NOT NULL
    AND (
      lower(di.label) LIKE '%liraglutide%' OR
      lower(di.label) LIKE '%semaglutide%' OR
      lower(di.label) LIKE '%dulaglutide%' OR
      lower(di.label) LIKE '%exenatide%' OR
      lower(di.label) LIKE '%lixisenatide%' OR
      lower(di.label) LIKE '%albiglutide%' OR
      lower(di.label) LIKE '%tirzepatide%'
    )
),

-- Step 5: De-correlate: join med_admins to cohort and aggregate per hadm_id to get flags
med_flags AS (
  SELECT
    c.hadm_id,
    MAX(IF(m.medtime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR), 1, 0)) = 1 AS received_first_12h,
    MAX(IF(m.medtime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime, 1, 0)) = 1 AS received_final_12h
  FROM cohort c
  LEFT JOIN med_admins m
    ON c.hadm_id = m.hadm_id
  GROUP BY c.hadm_id
),

-- Step 6: Ensure every cohort admission has explicit boolean flags (default false when no meds)
hadm_flags AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    COALESCE(mf.received_first_12h, FALSE) AS received_first_12h,
    COALESCE(mf.received_final_12h, FALSE) AS received_final_12h
  FROM cohort c
  LEFT JOIN med_flags mf
    ON c.hadm_id = mf.hadm_id
)

-- Final aggregation: counts, percentages, net change
SELECT
  COUNT(*) AS total_admissions_in_cohort,
  SUM(CASE WHEN received_first_12h THEN 1 ELSE 0 END) AS count_received_first_12h,
  SUM(CASE WHEN received_final_12h THEN 1 ELSE 0 END) AS count_received_final_12h,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN received_first_12h THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_received_first_12h,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN received_final_12h THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_received_final_12h,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN received_final_12h THEN 1 ELSE 0 END) - SUM(CASE WHEN received_first_12h THEN 1 ELSE 0 END), COUNT(*)), 2) AS net_change_pct_final_minus_first
FROM hadm_flags;
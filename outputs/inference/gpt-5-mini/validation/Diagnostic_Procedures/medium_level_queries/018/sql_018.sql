WITH cohort_admissions AS (
  -- Admissions for female patients age 80-90 with a diagnosis indicating hemorrhagic stroke
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON dx.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON dx.icd_code = dic.icd_code
   AND dx.icd_version = dic.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    -- Broad textual match for hemorrhagic stroke descriptions
    AND (
      LOWER(COALESCE(dic.long_title, '')) LIKE '%hemorrhag%'     -- hemorrhagic / haemorrhagic
      OR LOWER(COALESCE(dic.long_title, '')) LIKE '%subarachnoid%'
      OR LOWER(COALESCE(dic.long_title, '')) LIKE '%intracerebral%'
    )
),

-- Ultrasound events from hospital HCPCS events
hcpcs_ultrasounds AS (
  SELECT
    h.hadm_id,
    -- create a reasonably unique event id per row
    CONCAT('hcpcs|', h.hcpcs_cd, '|', CAST(h.chartdate AS STRING), '|', CAST(h.seq_num AS STRING)) AS event_uid,
    DATE(h.chartdate) AS event_date
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(COALESCE(h.short_description, dh.long_description, '')) LIKE '%ultrasound%'
),

-- Ultrasound events from hospital ICD procedures table (text match)
procicd_ultrasounds AS (
  SELECT
    p.hadm_id,
    CONCAT('procicd|', p.icd_code, '|', CAST(p.chartdate AS STRING), '|', CAST(p.seq_num AS STRING)) AS event_uid,
    DATE(p.chartdate) AS event_date
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON p.icd_code = dpr.icd_code
   AND p.icd_version = dpr.icd_version
  WHERE LOWER(COALESCE(dpr.long_title, '')) LIKE '%ultrasound%'
),

-- Ultrasound events from ICU procedureevents (d_items label)
icu_proc_ultrasounds AS (
  SELECT
    pe.hadm_id,
    CONCAT('icu_proc|', CAST(pe.itemid AS STRING), '|', CAST(pe.starttime AS STRING), '|', CAST(pe.caregiver_id AS STRING)) AS event_uid,
    DATE(pe.starttime) AS event_date,
    pe.starttime AS event_ts
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(COALESCE(di.label, '')) LIKE '%ultrasound%'
),

-- Combine all ultrasound event sources, and keep only those that fall within the admission window
all_ultrasound_events AS (
  SELECT
    c.hadm_id,
    ue.event_uid,
    ue.event_date,
    ue.event_ts
  FROM cohort_admissions c
  LEFT JOIN (
    -- hcpcs events: chartdate is a DATE
    SELECT hadm_id, event_uid, event_date, NULL AS event_ts FROM hcpcs_ultrasounds
    UNION ALL
    -- procedures_icd: chartdate is a DATE
    SELECT hadm_id, event_uid, event_date, NULL AS event_ts FROM procicd_ultrasounds
    UNION ALL
    -- ICU procedureevents: hadm_id, event_date, event_ts
    SELECT hadm_id, event_uid, event_date, event_ts FROM icu_proc_ultrasounds
  ) ue
    ON ue.hadm_id = c.hadm_id
  WHERE ue.event_uid IS NOT NULL
    -- For date-based events (event_date) ensure event_date between admission and discharge dates
    AND (
      (ue.event_ts IS NULL AND ue.event_date BETWEEN DATE(c.admittime) AND DATE(c.dischtime))
      OR
      -- for timestamp events (icu), ensure timestamp between admit and discharge timestamps
      (ue.event_ts IS NOT NULL AND ue.event_ts BETWEEN c.admittime AND c.dischtime)
    )
),

-- Count unique ultrasound events per admission; include admissions with zero events
ultrasounds_per_admission AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    -- compute LOS in days as inclusive days (same-day stay -> 1)
    DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) + 1 AS los_days,
    COALESCE(u.count_ultrasound, 0) AS num_ultrasounds
  FROM cohort_admissions c
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT event_uid) AS count_ultrasound
    FROM all_ultrasound_events
    GROUP BY hadm_id
  ) u
    ON c.hadm_id = u.hadm_id
)

-- Final aggregation: mean, min, max ultrasounds per admission for LOS groups 1-4 and 5-7
SELECT
  los_group,
  COUNT(*) AS admission_count,
  ROUND(AVG(num_ultrasounds), 3) AS mean_ultrasounds_per_admission,
  MIN(num_ultrasounds) AS min_ultrasounds_per_admission,
  MAX(num_ultrasounds) AS max_ultrasounds_per_admission
FROM (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group,
    num_ultrasounds
  FROM ultrasounds_per_admission
)
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY los_group;
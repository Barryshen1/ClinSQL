WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Hospital LOS in whole days (truncated)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- require an ACS-related diagnosis on the admission (textual match on ICD description)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dict
        ON di.icd_code = dict.icd_code
        AND di.icd_version = dict.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          LOWER(COALESCE(dict.long_title, '')) LIKE '%acute coronary%'
          OR LOWER(COALESCE(dict.long_title, '')) LIKE '%myocardial infarction%'
          OR LOWER(COALESCE(dict.long_title, '')) LIKE '%myocardial ischemia%'
          OR LOWER(COALESCE(dict.long_title, '')) LIKE '%unstable angina%'
          OR LOWER(COALESCE(dict.long_title, '')) LIKE '%acute mi%'
          OR LOWER(COALESCE(dict.long_title, '')) LIKE '%stemi%'
          OR LOWER(COALESCE(dict.long_title, '')) LIKE '%nstemi%'
          OR LOWER(COALESCE(dict.long_title, '')) LIKE '%coronary syndrome%'
        )
    )
    -- Limit to LOS between 1 and 7 days (we'll bucket 1-3 vs 4-7)
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- HCPCS events (HOSP) with likely ultrasound/echo descriptions
hcpcs_ultrasound AS (
  SELECT
    he.hadm_id,
    DATE(he.chartdate) AS event_date,
    'hcpcsevent' AS src
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
  WHERE
    -- textual match for ultrasound/echocardiography in the description
    (LOWER(COALESCE(he.short_description, '')) LIKE '%ultrasound%'
     OR LOWER(COALESCE(he.short_description, '')) LIKE '%echocardi%')
),

-- Procedures ICD (HOSP) with likely ultrasound/echo descriptions (chartdate is a DATE)
procs_icd_ultrasound AS (
  SELECT
    pi.hadm_id,
    pi.chartdate AS event_date,
    'procedures_icd' AS src
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
  ON
    pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE
    LOWER(COALESCE(dip.long_title, '')) LIKE '%ultrasound%'
    OR LOWER(COALESCE(dip.long_title, '')) LIKE '%echocardi%'
),

-- ICU procedureevents with d_items labels / value text matching ultrasound/echo
icu_proc_ultrasound AS (
  SELECT
    pe.hadm_id,
    -- prefer starttime; cast to DATE for joining on admission date-range as needed
    DATE(COALESCE(pe.starttime, pe.endtime)) AS event_date,
    'procedureevent' AS src
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    pe.itemid = di.itemid
  WHERE
    -- match either the d_items.label or the free-text value field
    (LOWER(COALESCE(di.label, '')) LIKE '%ultrasound%'
     OR LOWER(COALESCE(di.label, '')) LIKE '%echocardi%'
     OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%ultrasound%'
     OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%echocardi%')
),

-- Combine all candidate ultrasound events and restrict them to occur during the hospital admission window
combined_us_events AS (
  SELECT
    c.hadm_id,
    ce.event_date
  FROM cohort_admissions c
  JOIN hcpcs_ultrasound ce
    ON ce.hadm_id = c.hadm_id
    AND DATE(c.admittime) <= ce.event_date
    AND ce.event_date <= DATE(c.dischtime)

  UNION ALL

  SELECT
    c.hadm_id,
    ce.event_date
  FROM cohort_admissions c
  JOIN procs_icd_ultrasound ce
    ON ce.hadm_id = c.hadm_id
    AND DATE(c.admittime) <= ce.event_date
    AND ce.event_date <= DATE(c.dischtime)

  UNION ALL

  SELECT
    c.hadm_id,
    ce.event_date
  FROM cohort_admissions c
  JOIN icu_proc_ultrasound ce
    ON ce.hadm_id = c.hadm_id
    AND DATE(c.admittime) <= ce.event_date
    AND ce.event_date <= DATE(c.dischtime)
),

-- Count ultrasound events per admission (admissions with zero events will be left in the next step)
us_count_per_admission AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    -- bucket
    CASE
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'other'
    END AS los_bucket,
    COALESCE(e.us_count, 0) AS ultrasound_count
  FROM
    cohort_admissions c
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(1) AS us_count
    FROM
      combined_us_events
    GROUP BY hadm_id
  ) e
  ON c.hadm_id = e.hadm_id
)

-- Final aggregation: per LOS bucket get patient counts and mean ultrasounds per admission
SELECT
  los_bucket,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(hadm_id) AS admissions_count,
  ROUND(AVG(ultrasound_count), 3) AS mean_ultrasounds_per_admission
FROM
  us_count_per_admission
WHERE
  los_bucket IN ('1-3 days', '4-7 days')
GROUP BY
  los_bucket
ORDER BY
  -- show shorter LOS first
  CASE los_bucket WHEN '1-3 days' THEN 1 WHEN '4-7 days' THEN 2 ELSE 3 END;
WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admission_type,
    a.admission_location,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE
      WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
      WHEN a.admission_location = 'EMERGENCY ROOM ADMIT' THEN 'ED'
      ELSE NULL
    END AS admit_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
    -- Only keep ED or elective
    AND (
      a.admission_type = 'ELECTIVE'
      OR a.admission_location = 'EMERGENCY ROOM ADMIT'
    )
),

us_counts AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(*) AS us_events
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    (
      UPPER(h.short_description) LIKE '%ULTRASOUND%'
      OR UPPER(d.long_description) LIKE '%ULTRASOUND%'
      OR UPPER(h.short_description) LIKE '%ECHO%'
      OR UPPER(d.long_description) LIKE '%ECHO%'
    )
  GROUP BY
    h.subject_id,
    h.hadm_id
)

SELECT
  c.admit_category,
  CASE
    WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_bucket,
  ROUND(AVG(COALESCE(u.us_events, 0)), 2) AS mean_ultrasounds,
  MIN(COALESCE(u.us_events, 0)) AS min_ultrasounds,
  MAX(COALESCE(u.us_events, 0)) AS max_ultrasounds,
  COUNT(*) AS admissions_in_group
FROM
  cohort c
  LEFT JOIN us_counts u
    ON c.subject_id = u.subject_id
    AND c.hadm_id = u.hadm_id
GROUP BY
  admit_category,
  los_bucket
ORDER BY
  admit_category,
  los_bucket;
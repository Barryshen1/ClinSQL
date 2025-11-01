WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),
device_counts AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT di.itemid) AS device_count
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON c.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON icu.stay_id = pe.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
      AND (
        LOWER(di.label) LIKE '%assist%'
        OR LOWER(di.label) LIKE '%balloon%'
        OR LOWER(di.label) LIKE '%ecmo%'
      )
  GROUP BY
    c.hadm_id
)
SELECT
  -- median number of distinct mechanical circulatory support devices per hospitalization
  APPROX_QUANTILES(device_count, 2)[OFFSET(1)] AS median_device_count
FROM
  device_counts;
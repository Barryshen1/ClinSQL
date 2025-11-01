WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(CAST(a.dischtime AS DATE),
              CAST(a.admittime AS DATE),
              DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(CAST(a.dischtime AS DATE),
                     CAST(a.admittime AS DATE),
                     DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(CAST(a.dischtime AS DATE),
                     CAST(a.admittime AS DATE),
                     DAY) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND LOWER(dd.long_title) LIKE '%septic shock%'
    AND DATE_DIFF(CAST(a.dischtime AS DATE),
                  CAST(a.admittime AS DATE),
                  DAY) BETWEEN 1
              AND 7
  GROUP BY
    a.subject_id,
    a.hadm_id,
    los_days,
    los_group
),
icu_flag AS (
  SELECT
    hadm_id,
    'ICU' AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    hadm_id
),
us_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS us_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    LOWER(d.long_description) LIKE '%ultrasound%'
    OR LOWER(d.short_description) LIKE '%ultrasound%'
    OR LOWER(d.long_description) LIKE '%echo%'
    OR LOWER(d.short_description) LIKE '%echo%'
  GROUP BY
    h.hadm_id
)

SELECT
  t.los_group,
  t.icu_status,
  t.quantiles[SAFE_OFFSET(1)] AS p25,
  t.quantiles[SAFE_OFFSET(2)] AS p50,
  t.quantiles[SAFE_OFFSET(3)] AS p75
FROM (
  SELECT
    los_group,
    icu_status,
    APPROX_QUANTILES(us_count, 4) AS quantiles
  FROM (
    SELECT
      c.hadm_id,
      c.los_group,
      COALESCE(i.icu_status, 'No ICU') AS icu_status,
      COALESCE(u.us_count, 0)   AS us_count
    FROM
      cohort c
      LEFT JOIN icu_flag i USING (hadm_id)
      LEFT JOIN us_counts u USING (hadm_id)
  )
  GROUP BY
    los_group,
    icu_status
) AS t
ORDER BY
  t.los_group,
  t.icu_status;
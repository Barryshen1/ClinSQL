WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),

acs_flags AS (
  SELECT
    d.hadm_id,
    MIN(d.seq_num) AS min_seq
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_version = 9
    AND (
      d.icd_code LIKE '410%'    -- acute MI
      OR d.icd_code LIKE '411%' -- unstable angina
    )
  GROUP BY
    d.hadm_id
),

acs_labeled AS (
  SELECT
    hadm_id,
    CASE
      WHEN min_seq = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS acs_primary
  FROM
    acs_flags
),

ultrasound_counts AS (
  SELECT
    h.hadm_id,
    COUNT(1) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    (
      LOWER(h.short_description) LIKE '%ultrasound%'
      OR LOWER(d.long_description) LIKE '%ultrasound%'
      OR LOWER(h.short_description) LIKE '%echo%'
      OR LOWER(d.long_description) LIKE '%echo%'
    )
  GROUP BY
    h.hadm_id
)

SELECT
  los_group,
  acs_primary,
  quantiles[OFFSET(25)] AS p25_ultrasounds,
  quantiles[OFFSET(50)] AS p50_ultrasounds,
  quantiles[OFFSET(75)] AS p75_ultrasounds
FROM (
  SELECT
    c.los_group,
    a.acs_primary,
    APPROX_QUANTILES(IFNULL(uc.ultrasound_count, 0), 100) AS quantiles
  FROM
    cohort c
    JOIN acs_labeled a
      ON c.hadm_id = a.hadm_id
    LEFT JOIN ultrasound_counts uc
      ON c.hadm_id = uc.hadm_id
  GROUP BY
    c.los_group,
    a.acs_primary
)
ORDER BY
  los_group,
  acs_primary;
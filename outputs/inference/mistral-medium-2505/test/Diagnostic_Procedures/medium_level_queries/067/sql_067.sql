WITH
-- Get male patients aged 39-49 at admission
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 39 AND 49
),

-- Identify ACS admissions (primary and secondary)
acs_admissions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.age_at_admission,
    pa.los_days,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS acs_type
  FROM
    patient_admissions pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    pa.hadm_id = d.hadm_id
  WHERE
    -- ACS ICD-9 codes (410.xx) and ICD-10 codes (I21.x)
    (d.icd_version = 9 AND d.icd_code LIKE '410.%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
    AND pa.los_days BETWEEN 1 AND 7
),

-- Count ultrasounds/echos per admission
ultrasound_counts AS (
  SELECT
    aa.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN h.hcpcs_cd IN ('76700', '76705', '76770', '76775', '76776', '93306', '93307', '93308')
        THEN CONCAT(h.hadm_id, h.hcpcs_cd, h.seq_num)
        ELSE NULL
      END
    ) AS ultrasound_count
  FROM
    acs_admissions aa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  ON
    aa.hadm_id = h.hadm_id
  GROUP BY
    aa.hadm_id
),

-- Compute percentiles
percentiles AS (
  SELECT
    CASE
      WHEN aa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      ELSE '5-7 days'
    END AS los_group,
    aa.acs_type,
    PERCENTILE_CONT(uc.ultrasound_count, 0.25) OVER(PARTITION BY
      CASE
        WHEN aa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
        ELSE '5-7 days'
      END,
      aa.acs_type
    ) AS p25,
    PERCENTILE_CONT(uc.ultrasound_count, 0.5) OVER(PARTITION BY
      CASE
        WHEN aa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
        ELSE '5-7 days'
      END,
      aa.acs_type
    ) AS p50,
    PERCENTILE_CONT(uc.ultrasound_count, 0.75) OVER(PARTITION BY
      CASE
        WHEN aa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
        ELSE '5-7 days'
      END,
      aa.acs_type
    ) AS p75
  FROM
    acs_admissions aa
  LEFT JOIN
    ultrasound_counts uc
  ON
    aa.hadm_id = uc.hadm_id
)

-- Final aggregation
SELECT DISTINCT
  los_group,
  acs_type,
  p25,
  p50,
  p75
FROM
  percentiles
ORDER BY
  los_group,
  acs_type;
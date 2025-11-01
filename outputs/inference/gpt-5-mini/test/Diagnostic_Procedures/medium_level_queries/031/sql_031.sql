WITH akiselect AS (
  -- Admissions for female patients age 38-48 with an AKI diagnosis and LOS between 1 and 7 days
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), DAY) AS los_days,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
      LIMIT 1
    ) AS icu_used
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    -- AKI diagnosis: ICD-9 584.* or ICD-10 N17.*
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '584'))
          OR (d.icd_version = 10 AND STARTS_WITH(UPPER(d.icd_code), 'N17'))
        )
      LIMIT 1
    )
    AND TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), DAY) BETWEEN 1 AND 7
),

per_admission_counts AS (
  -- For each selected admission, count events in labevents, microbiologyevents, and hcpcsevents inside the admission window
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.los_days,
    c.icu_used,
    CASE
      WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4'
      ELSE '5-7'
    END AS los_group,
    -- lab events (timestamped)
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.hadm_id = c.hadm_id
        AND le.charttime BETWEEN c.admittime AND c.dischtime
    ) AS lab_count,
    -- microbiology events (timestamped)
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
      WHERE me.hadm_id = c.hadm_id
        AND me.charttime BETWEEN c.admittime AND c.dischtime
    ) AS micro_count,
    -- HCPCS events (chartdate is a date)
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      WHERE hc.hadm_id = c.hadm_id
        AND DATE(hc.chartdate) BETWEEN DATE(c.admittime) AND DATE(c.dischtime)
    ) AS hcpcs_count
  FROM akiselect c
),

with_total AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    icu_used,
    los_group,
    COALESCE(lab_count, 0) + COALESCE(micro_count, 0) + COALESCE(hcpcs_count, 0) AS total_noninvasive_diag
  FROM per_admission_counts
)

SELECT
  icu_used,
  los_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(total_noninvasive_diag), 2) AS mean_noninvasive_diag,
  MIN(total_noninvasive_diag) AS min_noninvasive_diag,
  MAX(total_noninvasive_diag) AS max_noninvasive_diag
FROM with_total
GROUP BY icu_used, los_group
ORDER BY icu_used DESC, los_group;
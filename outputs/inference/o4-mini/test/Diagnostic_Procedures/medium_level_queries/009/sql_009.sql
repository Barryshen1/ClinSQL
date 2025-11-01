WITH tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(dicd.long_title) LIKE '%transient ischemic attack%'
    -- Only consider admissions with LOS 1–7 days
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

icu_flag AS (
  SELECT
    ta.*,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'YES' ELSE 'NO' END AS icu_used,
    CASE
      WHEN ta.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN ta.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM
    tia_admissions ta
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ta.hadm_id = icu.hadm_id
),

imaging_counts AS (
  SELECT
    f.hadm_id,
    f.los_group,
    f.icu_used,
    COUNT(he.hcpcs_cd) AS imaging_count
  FROM
    icu_flag f
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
      ON f.hadm_id = he.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` hc
      ON he.hcpcs_cd = hc.code
  WHERE
    (
      LOWER(CAST(hc.category AS STRING)) LIKE '%radiology%'
      OR LOWER(hc.long_description) LIKE '%ct%'
      OR LOWER(hc.long_description) LIKE '%x-ray%'
      OR LOWER(hc.long_description) LIKE '%mri%'
      OR LOWER(hc.long_description) LIKE '%ultrasound%'
    )
  GROUP BY
    f.hadm_id,
    f.los_group,
    f.icu_used
)

SELECT
  ic.los_group,
  ic.icu_used,
  -- Compute the 25th, 50th, and 75th percentiles of imaging_count
  APPROX_QUANTILES(ic.imaging_count, 100)[OFFSET(25)] AS p25_imaging,
  APPROX_QUANTILES(ic.imaging_count, 100)[OFFSET(50)] AS p50_imaging,
  APPROX_QUANTILES(ic.imaging_count, 100)[OFFSET(75)] AS p75_imaging
FROM
  imaging_counts ic
GROUP BY
  ic.los_group,
  ic.icu_used
ORDER BY
  ic.los_group,
  ic.icu_used;
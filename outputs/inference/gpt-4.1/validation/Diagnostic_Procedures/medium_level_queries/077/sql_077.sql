WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    -- Calculate LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

ultrasound_procs_hosp AS (
  -- Hospital-wide procedures: ICD codes
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
      ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  WHERE
    LOWER(dpr.long_title) LIKE '%ultrasound%'
    OR LOWER(dpr.long_title) LIKE '%echo%'
),

ultrasound_procs_icu AS (
  -- ICU procedures: procedureevents
  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id,
    pe.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%ultrasound%'
    OR LOWER(di.label) LIKE '%echo%'
),

ultrasound_counts AS (
  -- Count ultrasounds per admission (from both sources)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    -- ICU flag: will be filled later
    COUNT(DISTINCT uph.icd_code) AS hosp_ultrasound_count,
    0 AS icu_ultrasound_count
  FROM
    cohort c
    LEFT JOIN ultrasound_procs_hosp uph
      ON c.subject_id = uph.subject_id AND c.hadm_id = uph.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.los_days

  UNION ALL

  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    0 AS hosp_ultrasound_count,
    COUNT(DISTINCT upi.itemid) AS icu_ultrasound_count
  FROM
    cohort c
    LEFT JOIN ultrasound_procs_icu upi
      ON c.subject_id = upi.subject_id AND c.hadm_id = upi.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.los_days
),

ultrasound_per_admission AS (
  -- Sum counts per admission
  SELECT
    subject_id,
    hadm_id,
    los_days,
    SUM(hosp_ultrasound_count) + SUM(icu_ultrasound_count) AS ultrasound_count
  FROM
    ultrasound_counts
  GROUP BY subject_id, hadm_id, los_days
),

icu_flag AS (
  -- For each admission, flag if there was an ICU stay
  SELECT DISTINCT
    hadm_id,
    1 AS had_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

final AS (
  SELECT
    upa.subject_id,
    upa.hadm_id,
    upa.los_days,
    upa.ultrasound_count,
    CASE
      WHEN upa.los_days >= 1 AND upa.los_days <= 3 THEN '1-3'
      WHEN upa.los_days > 3 AND upa.los_days <= 7 THEN '4-7'
      ELSE NULL
    END AS los_bucket,
    IF(i.hadm_id IS NOT NULL, 'ICU', 'No ICU') AS icu_group
  FROM
    ultrasound_per_admission upa
    LEFT JOIN icu_flag i
      ON upa.hadm_id = i.hadm_id
  WHERE
    upa.los_days >= 1 AND upa.los_days <= 7
)

SELECT
  los_bucket,
  icu_group,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(3)] AS p75,
  COUNT(*) AS n_admissions
FROM
  final
WHERE
  los_bucket IS NOT NULL
GROUP BY
  los_bucket, icu_group
ORDER BY
  los_bucket, icu_group;
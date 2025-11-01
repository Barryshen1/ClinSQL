WITH hf_admissions AS (
  -- Heart failure admissions, male, age 77-87
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
      -- ICD-10 I50.x or ICD-9 428.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
      OR
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
    )
),
icu_status AS (
  -- For each admission, determine if any ICU stay started within 24h of admission
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    h.anchor_age,
    h.gender,
    CASE
      WHEN MIN(i.intime) IS NOT NULL AND MIN(i.intime) <= h.admittime + INTERVAL 1 DAY THEN 'Day-1 ICU'
      ELSE 'Non-ICU'
    END AS icu_group
  FROM
    hf_admissions h
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON h.hadm_id = i.hadm_id
  GROUP BY
    h.subject_id, h.hadm_id, h.admittime, h.dischtime, h.hospital_expire_flag, h.anchor_age, h.gender
),
los_bins AS (
  -- Calculate LOS and bin
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) >= 8 THEN '8+'
      ELSE NULL
    END AS los_bin
  FROM
    icu_status
),
comorbidities AS (
  -- CKD and diabetes flags per admission
  SELECT
    hadm_id,
    MAX(CASE
      WHEN (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18'))
        OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585'))
      THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE
      WHEN (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]'))
        OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250'))
      THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
final AS (
  -- Merge LOS bins and comorbidities
  SELECT
    l.*,
    c.has_ckd,
    c.has_diabetes
  FROM
    los_bins l
    LEFT JOIN comorbidities c
      ON l.hadm_id = c.hadm_id
  WHERE
    l.los_bin IS NOT NULL
)
SELECT
  icu_group,
  los_bin,
  COUNT(*) AS n_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS mortality_percent,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(SUM(CASE WHEN has_ckd = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS ckd_percent,
  ROUND(SUM(CASE WHEN has_diabetes = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS diabetes_percent
FROM
  final
GROUP BY
  icu_group,
  los_bin
ORDER BY
  icu_group,
  los_bin;
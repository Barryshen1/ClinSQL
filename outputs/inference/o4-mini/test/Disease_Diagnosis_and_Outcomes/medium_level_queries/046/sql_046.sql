WITH hf_admissions AS (
  -- Identify admissions of 72-82yo males with any HF diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
admit_with_flags AS (
  -- Add ICU flag, compute LOS days, comorbidity count
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hospital_expire_flag,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) AS los_days,
    CASE 
      WHEN icustay.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_flag,
    -- Bucket LOS
    CASE
      WHEN TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) <= 3 THEN '0-3'
      WHEN TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) BETWEEN 4 AND 6 THEN '4-6'
      WHEN TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_bucket,
    -- Count distinct diagnoses per admission as comorbidity count
    (
      SELECT COUNT(DISTINCT icd_code)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = h.hadm_id
    ) AS comorb_count
  FROM
    hf_admissions AS h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustay
    ON h.hadm_id = icustay.hadm_id
)
SELECT
  icu_flag,
  los_bucket,
  COUNT(*) AS n_admissions,
  ROUND(100 * AVG(hospital_expire_flag), 1) AS pct_mortality,
  -- Approximate median LOS
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(AVG(comorb_count), 2) AS avg_comorbidity_count
FROM
  admit_with_flags
GROUP BY
  icu_flag,
  los_bucket
ORDER BY
  icu_flag,
  los_bucket;
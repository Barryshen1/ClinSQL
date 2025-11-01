WITH hf_admissions AS (
  -- Admissions of male patients age 72-82 with any diagnosis whose description contains "heart failure"
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- integer LOS in days: count partial day as 1 (typical reporting)
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) AS los_days,
    -- fractional LOS in days for more precise median
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days_exact
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dic.long_title) LIKE '%heart failure%'
    )
),

comorb_counts AS (
  -- For each admission, count distinct diagnosis codes excluding diagnoses whose description contains "heart failure"
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS distinct_diag_count_excl_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE
    LOWER(dic.long_title) NOT LIKE '%heart failure%'
  GROUP BY
    d.hadm_id
),

hf_with_flags AS (
  -- Combine HF admissions with comorbidity counts and ICU flag
  SELECT
    h.subject_id,
    h.hadm_id,
    h.anchor_age,
    h.gender,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    h.los_days,
    h.los_days_exact,
    COALESCE(c.distinct_diag_count_excl_hf, 0) AS comorb_count,
    -- ICU flag: 1 if any icustay exists for this hadm_id, else 0
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = h.hadm_id
    ) THEN 1 ELSE 0 END AS icu_flag
  FROM
    hf_admissions h
  LEFT JOIN
    comorb_counts c
  ON h.hadm_id = c.hadm_id
)

SELECT
  CASE WHEN icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS care_location,
  CASE
    WHEN los_days <= 3 THEN '<=3'
    WHEN los_days BETWEEN 4 AND 6 THEN '4-6'
    WHEN los_days BETWEEN 7 AND 10 THEN '7-10'
    ELSE '>10'
  END AS los_category,
  COUNT(*) AS admissions_count,
  -- mortality rate as proportion (0-1); multiply by 100 if percent desired
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate_proportion,
  -- approximate median LOS (days) using fractional LOS for precision
  APPROX_QUANTILES(los_days_exact, 100)[OFFSET(50)] AS median_los_days_approx,
  -- average comorbidity count (excluding heart failure diagnoses)
  ROUND(AVG(comorb_count), 2) AS avg_comorbidity_count
FROM
  hf_with_flags
GROUP BY
  icu_flag,
  los_category
ORDER BY
  icu_flag DESC,
  -- order the LOS categories naturally
  CASE
    WHEN los_category = '<=3' THEN 1
    WHEN los_category = '4-6' THEN 2
    WHEN los_category = '7-10' THEN 3
    ELSE 4
  END;
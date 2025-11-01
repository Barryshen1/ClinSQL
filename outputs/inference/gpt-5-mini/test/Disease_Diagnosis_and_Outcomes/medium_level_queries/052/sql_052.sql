WITH stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- ICU vs Non-ICU: exists any icustays row for this hadm_id
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    ) THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    -- Hospital LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    -- Require a stroke diagnosis on this admission (text-based match on diagnosis description)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%stroke%'
          OR LOWER(dd.long_title) LIKE '%cerebrovascular%'
        )
    )
    -- require non-null times to compute LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Compute per-admission diagnosis counts and flags for CKD and diabetes
hadm_diagnoses AS (
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS num_distinct_dx,
    MAX(CASE WHEN
         LOWER(dd.long_title) LIKE '%chronic kidney%'
      OR LOWER(dd.long_title) LIKE '%chronic renal%'
      OR LOWER(dd.long_title) LIKE '%ckd%'
      OR LOWER(dd.long_title) LIKE '%end stage renal%'
      THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabet%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  GROUP BY d.hadm_id
),

-- Join cohort to diagnosis-derived measures and compute comorbidity tertiles
hadm_with_comorb AS (
  SELECT
    s.*,
    COALESCE(h.num_distinct_dx, 0) AS num_distinct_dx,
    COALESCE(h.has_ckd, 0) AS has_ckd,
    COALESCE(h.has_diabetes, 0) AS has_diabetes,
    -- tertile across the cohort based on num_distinct_dx (1 = lowest tertile)
    NTILE(3) OVER (ORDER BY COALESCE(h.num_distinct_dx, 0)) AS comorbidity_tertile
  FROM stroke_admissions s
  LEFT JOIN hadm_diagnoses h
    ON s.hadm_id = h.hadm_id
),

-- Final aggregation: stratify by ICU group, LOS group, and comorbidity tertile
final_stats AS (
  SELECT
    icu_group,
    CASE WHEN hosp_los_days <= 5 THEN '<=5 days' ELSE '>5 days' END AS los_group,
    comorbidity_tertile,
    COUNT(*) AS admissions_n,
    SUM(CAST(hospital_expire_flag AS INT64)) AS deaths_n,
    SUM(CAST(has_ckd AS INT64)) AS ckd_n,
    SUM(CAST(has_diabetes AS INT64)) AS diabetes_n
  FROM hadm_with_comorb
  GROUP BY icu_group, los_group, comorbidity_tertile
)

SELECT
  icu_group,
  los_group,
  comorbidity_tertile,
  admissions_n,
  deaths_n,
  ROUND(100.0 * SAFE_DIVIDE(deaths_n, admissions_n), 1) AS mortality_percent,
  ckd_n,
  ROUND(100.0 * SAFE_DIVIDE(ckd_n, admissions_n), 1) AS ckd_percent,
  diabetes_n,
  ROUND(100.0 * SAFE_DIVIDE(diabetes_n, admissions_n), 1) AS diabetes_percent
FROM final_stats
ORDER BY icu_group, los_group, comorbidity_tertile;
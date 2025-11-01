WITH hf_admissions AS (
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
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
adm_with_metrics AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hospital_expire_flag,
    -- ICU flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
      WHERE ic.hadm_id = h.hadm_id
    ) THEN 'ICU' ELSE 'No_ICU' END AS icu_flag,
    -- Hospital LOS in days
    GREATEST(
      1,
      TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY)
    ) AS los_days,
    -- Comorbidity count: distinct ICD diagnoses on this admission excluding HF codes
    (
      SELECT COUNT(DISTINCT dx.icd_code)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
        ON dx.icd_code = ddx.icd_code
        AND dx.icd_version = ddx.icd_version
      WHERE dx.hadm_id = h.hadm_id
        AND LOWER(ddx.long_title) NOT LIKE '%heart failure%'
    ) AS comorb_count
  FROM hf_admissions h
),
stratified AS (
  SELECT
    icu_flag,
    -- LOS category
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '8+' END AS los_cat,
    -- Charlson (proxy) category
    CASE
      WHEN comorb_count <= 3 THEN '<=3'
      WHEN comorb_count BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5' END AS charlson_cat,
    hospital_expire_flag,
    comorb_count
  FROM adm_with_metrics
)
SELECT
  icu_flag,
  los_cat,
  charlson_cat,
  COUNT(1) AS n_admissions,
  SUM(hospital_expire_flag) AS deaths,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) AS mortality_rate,
  -- 95% CI for proportion
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1))
    - 1.96 * SQRT(
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1))
        * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)))
        / COUNT(1)
      ) AS mortality_ci_lower,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1))
    + 1.96 * SQRT(
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1))
        * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)))
        / COUNT(1)
      ) AS mortality_ci_upper,
  AVG(comorb_count) AS mean_comorbidity_count
FROM stratified
GROUP BY icu_flag, los_cat, charlson_cat
ORDER BY icu_flag, los_cat, charlson_cat;
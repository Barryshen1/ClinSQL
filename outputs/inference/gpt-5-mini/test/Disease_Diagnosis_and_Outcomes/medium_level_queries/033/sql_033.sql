WITH
-- Admissions for male patients aged 82-92 that have at least one postoperative-complication diagnosis
postop_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- ICU flag: true if any icustay exists for this hadm_id
    EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    ) AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND EXISTS (
      -- presence of a postoperative-complication diagnosis on this admission
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          -- ICD-9 postoperative complication codes (common pattern)
          (di.icd_version = 9 AND SAFE_CAST(SUBSTR(di.icd_code, 1, 3) AS STRING) LIKE '998')
          OR
          -- ICD-10 postoperative complication codes (common pattern)
          (di.icd_version = 10 AND STARTS_WITH(di.icd_code, 'T81'))
          OR
          -- textual match on d_icd_diagnoses long title (covers variations)
          LOWER(COALESCE(dd.long_title, '')) LIKE '%postoper%'
        )
      LIMIT 1
    )
),

-- For each hadm_id compute comorbidity count = distinct diagnosis codes excluding postoperative-complication codes
hadm_comorbs AS (
  SELECT
    di.hadm_id,
    COUNT(DISTINCT CASE
      WHEN (
        (di.icd_version = 9 AND STARTS_WITH(di.icd_code, '998'))
        OR (di.icd_version = 10 AND STARTS_WITH(di.icd_code, 'T81'))
        OR LOWER(COALESCE(dd.long_title, '')) LIKE '%postoper%'
      ) THEN NULL
      ELSE di.icd_code
    END) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
)

-- Final aggregation by ICU vs non-ICU, LOS bin, and comorbidity bin
SELECT
  CASE WHEN pa.icu_flag THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  CASE WHEN pa.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_bin,
  CASE
    WHEN COALESCE(hc.comorb_count, 0) <= 1 THEN '0-1'
    WHEN COALESCE(hc.comorb_count, 0) = 2 THEN '2'
    ELSE '>=3'
  END AS comorbidity_bin,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(CAST(pa.hospital_expire_flag AS INT64)) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(AVG(COALESCE(hc.comorb_count, 0)), 2) AS avg_comorbidity_count
FROM postop_admissions pa
LEFT JOIN hadm_comorbs hc
  ON pa.hadm_id = hc.hadm_id
GROUP BY icu_status, los_bin, comorbidity_bin
ORDER BY icu_status, los_bin, comorbidity_bin;
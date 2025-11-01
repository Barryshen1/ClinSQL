WITH hf_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND SAFE_CAST(d.icd_version AS STRING) = SAFE_CAST(dd.icd_version AS STRING)
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
),

-- Comorbidity count per admission excluding heart failure diagnoses
comorb_counts AS (
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorb_count_all,
    COUNT(DISTINCT CASE
      WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%' THEN NULL
      ELSE d.icd_code
    END) AS comorb_count_excluding_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND SAFE_CAST(d.icd_version AS STRING) = SAFE_CAST(dd.icd_version AS STRING)
  GROUP BY d.hadm_id
),

-- Build cohort with LOS and comorbidity count
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- LOS in fractional days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days,
    COALESCE(cc.comorb_count_excluding_hf, 0) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hf_admissions hf
    ON a.hadm_id = hf.hadm_id
  LEFT JOIN comorb_counts cc
    ON a.hadm_id = cc.hadm_id
  WHERE
    -- male patients age window 43-53
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 43 AND 53
    -- require valid admittime/dischtime to compute LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Assign LOS quartiles and comorbidity tertiles (relative to this cohort)
cohort_with_bins AS (
  SELECT
    c.*,
    NTILE(4) OVER (ORDER BY c.los_days) AS los_quartile,
    NTILE(3) OVER (ORDER BY c.comorb_count) AS comorb_tertile
  FROM cohort c
)

-- Final aggregation: mortality % by LOS quartile x comorbidity burden (low/med/high)
SELECT
  los_quartile,
  CASE
    WHEN comorb_tertile = 1 THEN 'Low'
    WHEN comorb_tertile = 2 THEN 'Medium'
    WHEN comorb_tertile = 3 THEN 'High'
    ELSE 'Unknown'
  END AS comorbidity_group,
  COUNT(*) AS n_admissions,
  SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS NUMERIC)) / GREATEST(COUNT(*), 1), 2) AS mortality_pct
FROM cohort_with_bins
GROUP BY los_quartile, comorb_tertile
ORDER BY los_quartile, comorb_tertile;
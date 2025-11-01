WITH postop_admissions AS (
  -- Admissions of male patients age 82-92 with at least one postoperative complication diagnosis
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dpc
      ON a.hadm_id = dpc.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON dpc.icd_code = dicd.icd_code
         AND dpc.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(dicd.long_title) LIKE '%postoperative%complication%'
  GROUP BY
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),

admission_metrics AS (
  -- Compute LOS, ICU flag, comorbidity count, and buckets
  SELECT
    pa.subject_id,
    pa.hadm_id,
    DATE_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    CASE WHEN icu.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS icu_flag,
    -- Count distinct ICD codes as comorbidity proxy
    COUNT(DISTINCT d.icd_code) AS comorb_count,
    pa.hospital_expire_flag
  FROM
    postop_admissions pa
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON pa.hadm_id = icu.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON pa.hadm_id = d.hadm_id
  GROUP BY
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    icu.hadm_id
),

binned_admissions AS (
  -- Apply LOS and comorbidity bins
  SELECT
    *,
    CASE
      WHEN los_days <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_bin,
    CASE
      WHEN comorb_count <= 1 THEN '0-1'
      WHEN comorb_count = 2 THEN '2'
      ELSE '≥3'
    END AS comorb_bin
  FROM
    admission_metrics
)

-- Final aggregation
SELECT
  CASE WHEN icu_flag THEN 'ICU' ELSE 'Non-ICU' END AS setting,
  los_bin,
  comorb_bin,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS in_hospital_mortality_pct,
  ROUND(AVG(comorb_count), 2) AS avg_comorbidity_count
FROM
  binned_admissions
GROUP BY
  setting,
  los_bin,
  comorb_bin
ORDER BY
  setting,
  los_bin,
  comorb_bin;
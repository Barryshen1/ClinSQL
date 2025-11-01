WITH heart_failure_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age,
    CAST(adm.admittime AS DATETIME) AS admittime,
    CAST(adm.dischtime AS DATETIME) AS dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 72 AND 82
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%') OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    )
),
icu_flags AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
comorbidity_counts AS (
  SELECT hadm_id,
    COUNT(DISTINCT CONCAT(icd_version, '-', icd_code)) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE NOT (
      (icd_version = 9 AND icd_code LIKE '428%') OR
      (icd_version = 10 AND icd_code LIKE 'I50%')
    )
  GROUP BY hadm_id
),
cohort AS (
  SELECT hfa.subject_id, hfa.hadm_id,
    IF(icuf.icu_flag IS NULL, 0, 1) AS icu_flag,
    DATETIME_DIFF(hfa.dischtime, hfa.admittime, DAY) AS los_days,
    hfa.hospital_expire_flag,
    COALESCE(cc.comorb_count, 0) AS comorb_count
  FROM heart_failure_admissions hfa
  LEFT JOIN icu_flags icuf
    ON hfa.hadm_id = icuf.hadm_id
  LEFT JOIN comorbidity_counts cc
    ON hfa.hadm_id = cc.hadm_id
),
cohort_with_bins AS (
  SELECT *,
    CASE
      WHEN los_days <= 3 THEN '≤3 days'
      WHEN los_days BETWEEN 4 AND 6 THEN '4-6 days'
      WHEN los_days BETWEEN 7 AND 10 THEN '7-10 days'
      WHEN los_days > 10 THEN '>10 days'
      ELSE 'Unknown'
    END AS los_bin
  FROM cohort
)
SELECT
  icu_flag,
  los_bin,
  COUNT(*) AS n_admissions,
  ROUND(AVG(hospital_expire_flag)*100,2) AS mortality_rate_percent,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(AVG(comorb_count),2) AS avg_comorbidity_count
FROM cohort_with_bins
GROUP BY icu_flag, los_bin
ORDER BY icu_flag, 
  CASE los_bin
    WHEN '≤3 days' THEN 1
    WHEN '4-6 days' THEN 2
    WHEN '7-10 days' THEN 3
    WHEN '>10 days' THEN 4
    ELSE 5
  END;
WITH hf_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
icu_flag AS (
  SELECT 
    h.subject_id,
    h.hadm_id,
    h.admittime,
    CASE WHEN MIN(i.intime) <= DATETIME_ADD(h.admittime, INTERVAL 1 DAY) THEN 1 ELSE 0 END AS icu_day1_flag
  FROM hf_admissions h
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON h.hadm_id = i.hadm_id
  GROUP BY h.subject_id, h.hadm_id, h.admittime
),
comorbid_flags AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') 
            OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
          THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') 
            OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'))
          THEN 1 ELSE 0 END) AS dm_flag
  FROM hf_admissions h
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON h.hadm_id = d.hadm_id
  GROUP BY h.subject_id, h.hadm_id
),
final_cohort AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    icu.icu_day1_flag,
    DATETIME_DIFF(h.dischtime, h.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(h.dischtime, h.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATETIME_DIFF(h.dischtime, h.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATETIME_DIFF(h.dischtime, h.admittime, DAY) >= 8 THEN '>=8'
      ELSE NULL
    END AS los_category,
    h.hospital_expire_flag,
    com.ckd_flag,
    com.dm_flag
  FROM hf_admissions h
  JOIN icu_flag icu
    ON h.subject_id = icu.subject_id AND h.hadm_id = icu.hadm_id
  JOIN comorbid_flags com
    ON h.subject_id = com.subject_id AND h.hadm_id = com.hadm_id
)
SELECT
  icu_day1_flag,
  los_category,
  COUNT(*) AS n_admissions,
  ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 1) AS mortality_percent,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(SUM(CASE WHEN ckd_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS ckd_percent,
  ROUND(SUM(CASE WHEN dm_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS dm_percent
FROM final_cohort
WHERE los_category IS NOT NULL
GROUP BY icu_day1_flag, los_category
ORDER BY icu_day1_flag DESC, los_category;
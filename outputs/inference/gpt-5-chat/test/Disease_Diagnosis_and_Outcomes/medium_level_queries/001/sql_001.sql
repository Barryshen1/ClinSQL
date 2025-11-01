WITH adhf_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- hospital LOS in days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      -- ICD-9 CHF: 428.x
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      -- ICD-10 CHF: I50.x
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
comorbidities AS (
  SELECT
    hadm_id,
    MAX(CASE 
        WHEN (icd_version = 9 AND icd_code LIKE '585%')
          OR (icd_version = 10 AND icd_code LIKE 'N18%')
        THEN 1 ELSE 0 END) AS ckd,
    MAX(CASE 
        WHEN (icd_version = 9 AND icd_code LIKE '250%')
          OR (icd_version = 10 AND (
               icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')
             )
        THEN 1 ELSE 0 END) AS dm
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
icu_day1 AS (
  SELECT
    a.hadm_id,
    CASE WHEN MIN(TIMESTAMP_DIFF(i.intime, a.admittime, HOUR)) <= 24 THEN 1 ELSE 0 END AS day1_icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  GROUP BY a.hadm_id
)
SELECT
  CASE WHEN c.los_days <= 7 THEN 'LOS <=7d' ELSE 'LOS >7d' END AS los_group,
  i.day1_icu_flag,
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(c.hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  ROUND(100 * SUM(cb.ckd) / COUNT(*), 1) AS ckd_pct,
  ROUND(100 * SUM(cb.dm) / COUNT(*), 1) AS dm_pct
FROM adhf_cohort c
LEFT JOIN comorbidities cb
  ON c.hadm_id = cb.hadm_id
LEFT JOIN icu_day1 i
  ON c.hadm_id = i.hadm_id
GROUP BY los_group, i.day1_icu_flag
ORDER BY los_group, i.day1_icu_flag;
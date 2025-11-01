WITH base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.subject_id = a.subject_id
          AND di.hadm_id = a.hadm_id
          AND (
            (di.icd_version = 9 AND di.icd_code LIKE '584%')
            OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
          )
      ) THEN 1 ELSE 0
    END AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'MALE'
    AND p.anchor_age BETWEEN 47 AND 57
),

lis_per_adm AS (
  SELECT b.hadm_id,
         COALESCE(STDDEV_SAMP(l.valuenum), 0) AS lis72
  FROM base b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = b.subject_id
   AND l.hadm_id = b.hadm_id
   AND l.charttime >= b.admittime
   AND l.charttime < TIMESTAMP_ADD(b.admittime, INTERVAL 72 HOUR)
   AND l.valuenum IS NOT NULL
  GROUP BY b.hadm_id
),

icu_counts AS (
  SELECT hadm_id, COUNT(*) AS icu_stay_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

los_per_adm AS (
  SELECT a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 3600.0 AS los_hr
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN base b ON b.hadm_id = a.hadm_id
)

SELECT
  b.aki_flag AS aki_group,
  AVG(lis72) AS mean_lis72,
  AVG(COALESCE(ic.icu_stay_count, 0)) AS avg_icu_stay_count,
  AVG(COALESCE(los.los_hr, 0)) AS avg_los_hrs,
  AVG(CASE WHEN b.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate
FROM base b
LEFT JOIN lis_per_adm lis ON lis.hadm_id = b.hadm_id
LEFT JOIN icu_counts ic ON ic.hadm_id = b.hadm_id
LEFT JOIN los_per_adm los ON los.hadm_id = b.hadm_id
GROUP BY b.aki_flag
ORDER BY b.aki_flag;
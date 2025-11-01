WITH ami_admissions AS (
  SELECT DISTINCT h.subject_id, h.hadm_id, h.admittime, h.dischtime, h.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON h.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = h.subject_id
        AND di.hadm_id = h.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%acute myocardial infarction%' OR
          LOWER(dd.long_title) LIKE '%myocardial infarction%'
        )
    )
),
day1_status AS (
  SELECT a.subject_id,
         a.hadm_id,
         CASE
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
             WHERE ic.hadm_id = a.hadm_id
               AND ic.intime >= a.admittime
               AND ic.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
           ) THEN 'ICU_on_day1'
           ELSE 'No_ICU_on_day1'
         END AS day1_icu_status,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
         a.hospital_expire_flag
  FROM ami_admissions a
),
enriched AS (
  SELECT s.day1_icu_status,
         CASE WHEN s.los_days <= 5.0 THEN '≤5' ELSE '>5' END AS los_group,
         s.los_days,
         s.hospital_expire_flag
  FROM day1_status s
),
grouped_stats AS (
  SELECT day1_icu_status,
         los_group,
         COUNT(*) AS n_patients,
         SUM(hospital_expire_flag) AS deaths,
         SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS in_hospital_mortality_percent
  FROM enriched
  GROUP BY day1_icu_status, los_group
),
median_vals AS (
  SELECT day1_icu_status,
         los_group,
         AVG(los_days) AS median_los_days
  FROM (
     SELECT day1_icu_status,
            los_group,
            los_days,
            ROW_NUMBER() OVER (
              PARTITION BY day1_icu_status, los_group
              ORDER BY los_days
            ) AS rn,
            COUNT(*) OVER (
              PARTITION BY day1_icu_status, los_group
            ) AS total_cnt
     FROM enriched
  )
  WHERE rn IN (FLOOR((total_cnt + 1) / 2), CEIL((total_cnt + 1) / 2))
  GROUP BY day1_icu_status, los_group
)
SELECT gs.day1_icu_status,
       gs.los_group,
       gs.n_patients,
       gs.deaths,
       gs.in_hospital_mortality_percent,
       mv.median_los_days
FROM grouped_stats gs
LEFT JOIN median_vals mv
  ON gs.day1_icu_status = mv.day1_icu_status
  AND gs.los_group = mv.los_group
ORDER BY gs.day1_icu_status, gs.los_group;
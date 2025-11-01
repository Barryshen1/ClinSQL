WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
      WHERE dx.hadm_id = a.hadm_id
        AND (
          dx.icd_code = '5770' -- ICD-9 acute pancreatitis
          OR dx.icd_code LIKE 'K85%' -- ICD-10 acute pancreatitis
          OR LOWER(dd.long_title) LIKE '%acute pancreatitis%'
        )
    )
),
dx_counts AS (
  SELECT c.subject_id, c.hadm_id, c.gender, c.anchor_age,
         c.admittime, c.dischtime, c.hospital_expire_flag,
         COUNT(*) AS diagnosis_count,
         SUM(
           CASE
             WHEN dx.icd_code LIKE '99591%' OR dx.icd_code LIKE '99592%' OR dx.icd_code LIKE 'A41%'
               OR LOWER(dd.long_title) LIKE '%sepsis%' THEN 1
             WHEN dx.icd_code LIKE '78550%' OR dx.icd_code LIKE 'R57%'
               OR LOWER(dd.long_title) LIKE '%shock%' THEN 1
             WHEN dx.icd_code LIKE '584%' OR dx.icd_code LIKE 'N17%'
               OR LOWER(dd.long_title) LIKE '%acute kidney%' THEN 1
             WHEN dx.icd_code LIKE '51881%' OR dx.icd_code LIKE 'J96%'
               OR LOWER(dd.long_title) LIKE '%respiratory failure%' THEN 1
             ELSE 0
           END
         ) AS major_complication_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON c.hadm_id = dx.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  GROUP BY c.subject_id, c.hadm_id, c.gender, c.anchor_age,
           c.admittime, c.dischtime, c.hospital_expire_flag
),
risk_scores AS (
  SELECT *,
         (diagnosis_count + 5 * major_complication_count) AS risk_score
  FROM dx_counts
),
quartiles AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile,
         TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM risk_scores
),
summary AS (
  SELECT CAST(risk_quartile AS STRING) AS quartile,
         COUNT(*) AS total_patients,
         SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
         SUM(CASE WHEN major_complication_count > 0 THEN 1 ELSE 0 END) AS patients_with_major_complication,
         SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
         SAFE_DIVIDE(SUM(CASE WHEN major_complication_count > 0 THEN 1 ELSE 0 END), COUNT(*)) AS major_complication_rate,
         APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_survivor_los_days
  FROM quartiles
  WHERE hospital_expire_flag = 0 -- survivors for LOS
  GROUP BY quartile
)
SELECT * FROM summary
UNION ALL
SELECT 'Overall' AS quartile,
       COUNT(*) AS total_patients,
       SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
       SUM(CASE WHEN major_complication_count > 0 THEN 1 ELSE 0 END) AS patients_with_major_complication,
       SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
       SAFE_DIVIDE(SUM(CASE WHEN major_complication_count > 0 THEN 1 ELSE 0 END), COUNT(*)) AS major_complication_rate,
       APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_survivor_los_days
FROM quartiles
WHERE hospital_expire_flag = 0
;
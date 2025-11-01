WITH ich_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    drg.drg_severity,
    drg.drg_mortality,
    -- example composite risk score
    p.anchor_age 
      + 2 * IFNULL(drg.drg_severity,0) 
      + 3 * IFNULL(drg.drg_mortality,0) AS composite_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON a.hadm_id = drg.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
),
quintiles AS (
  SELECT
    ic.*,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM ich_cohort ic
),
complications AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%complication%'
)
SELECT
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(CASE 
    WHEN deathtime IS NOT NULL 
         AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30
    THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_30day_pct,
  ROUND(100.0 * SUM(CASE 
    WHEN q.hadm_id IN (
         SELECT hadm_id FROM complications
    )
    THEN 1 ELSE 0 END) / COUNT(*), 2) AS major_complication_pct,
  ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, DAY), 50)[OFFSET(25)],2) 
    AS median_survivor_los_days
FROM quintiles q
WHERE NOT (hospital_expire_flag = 1 
           OR (deathtime IS NOT NULL 
               AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30))
GROUP BY quintile
ORDER BY quintile;
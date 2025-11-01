WITH sepsis_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('995.92'))
      OR (d.icd_version = 10 AND d.icd_code IN ('R65.20'))
    )
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
      INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd2
        ON d2.icd_code = dicd2.icd_code AND d2.icd_version = dicd2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code = '785.52')
          OR (d2.icd_version = 10 AND d2.icd_code = 'R65.21')
        )
    )
),
mortality_los AS (
  SELECT
    CASE WHEN los_days <= 7 THEN 'LOS <=7' ELSE 'LOS >7' END AS los_group,
    hospital_expire_flag,
    CASE 
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL 
      THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
      ELSE NULL 
    END AS time_to_death_days
  FROM sepsis_patients
)
SELECT
  SUM(CASE WHEN los_group = 'LOS <=7' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
    COUNT(CASE WHEN los_group = 'LOS <=7' THEN 1 END) AS mortality_pct_los_leq7,
  SUM(CASE WHEN los_group = 'LOS >7' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
    COUNT(CASE WHEN los_group = 'LOS >7' THEN 1 END) AS mortality_pct_los_gt7,
  (SUM(CASE WHEN los_group = 'LOS >7' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
    COUNT(CASE WHEN los_group = 'LOS >7' THEN 1 END)) - 
  (SUM(CASE WHEN los_group = 'LOS <=7' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
    COUNT(CASE WHEN los_group = 'LOS <=7' THEN 1 END)) AS absolute_difference,
  ((SUM(CASE WHEN los_group = 'LOS >7' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
    COUNT(CASE WHEN los_group = 'LOS >7' THEN 1 END)) - 
   (SUM(CASE WHEN los_group = 'LOS <=7' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
    COUNT(CASE WHEN los_group = 'LOS <=7' THEN 1 END))) / 
   (SUM(CASE WHEN los_group = 'LOS <=7' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
    COUNT(CASE WHEN los_group = 'LOS <=7' THEN 1 END)) AS relative_difference,
  APPROX_QUANTILES(CASE WHEN los_group = 'LOS <=7' AND hospital_expire_flag = 1 THEN time_to_death_days END, 2)[OFFSET(1)] AS median_time_to_death_los_leq7,
  APPROX_QUANTILES(CASE WHEN los_group = 'LOS >7' AND hospital_expire_flag = 1 THEN time_to_death_days END, 2)[OFFSET(1)] AS median_time_to_death_los_gt7
FROM mortality_los;
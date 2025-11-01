WITH acute_hf_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
         a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(dd.long_title) LIKE '%acute%'
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
los_calc AS (
  SELECT *,
         DATE_DIFF(DISCHTIME, ADMITTIME, DAY) AS los_days,
         CASE
           WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
           WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
           WHEN DATE_DIFF(dischtime, admittime, DAY) >= 8 THEN '8+'
         END AS los_cat,
         CASE
           WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY)
         END AS ttd_days
  FROM acute_hf_admissions
)
SELECT
  los_cat,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
  ROUND(100 * (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) 
       - 1.96 * SQRT((SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*)) 
       * (1 - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*)) / COUNT(*))), 2) AS ci_lower_pct,
  ROUND(100 * (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) 
       + 1.96 * SQRT((SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*)) 
       * (1 - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*)) / COUNT(*))), 2) AS ci_upper_pct,
  ROUND(APPROX_QUANTILES(ttd_days, 100)[OFFSET(50)], 1) AS median_time_to_death_days
FROM los_calc
WHERE los_cat IS NOT NULL
GROUP BY los_cat
ORDER BY 
  CASE los_cat
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '8+' THEN 3
  END;
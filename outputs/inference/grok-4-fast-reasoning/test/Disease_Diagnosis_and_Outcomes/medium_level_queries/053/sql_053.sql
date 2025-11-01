WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 39 AND 49
),
admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM patients p
  INNER JOIN admissions a ON p.subject_id = a.subject_id
),
pneumonia_flags AS (
  SELECT hadm_id,
         MAX(CASE WHEN (icd_version = 9 AND icd_code = '507.0')
                  OR (icd_version = 10 AND (icd_code LIKE 'J69%' OR icd_code LIKE 'J70%'))
             THEN 1 ELSE 0 END) AS asp_flag,
         MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^48[0-6]'))
                  OR (icd_version = 10 AND icd_code LIKE 'J1[2-8]%')
             THEN 1 ELSE 0 END) AS comm_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_pneumonia AS (
  SELECT c.*, pf.asp_flag, pf.comm_flag,
         CASE WHEN pf.asp_flag = 1 THEN 'Aspiration'
              WHEN pf.comm_flag = 1 THEN 'Community-acquired'
              ELSE NULL END AS pneumonia_type,
         CASE WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3'
              WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7'
              ELSE '>=8' END AS los_cat
  FROM cohort c
  INNER JOIN pneumonia_flags pf ON c.hadm_id = pf.hadm_id
  WHERE pf.asp_flag = 1 OR pf.comm_flag = 1
),
icu_flags AS (
  SELECT i.hadm_id,
         MAX(CASE WHEN TIMESTAMP_DIFF(i.intime, cp.admittime, HOUR) <= 24 THEN 1 ELSE 0 END) AS icu_day1
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort_pneumonia cp ON i.hadm_id = cp.hadm_id
  GROUP BY i.hadm_id
),
comorb_counts AS (
  SELECT hadm_id, COUNT(*) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num > 1
  GROUP BY hadm_id
),
main_data AS (
  SELECT cp.*,
         COALESCE(icu.icu_day1, 0) AS icu_day1,
         COALESCE(com.comorb_count, 0) AS comorb_count
  FROM cohort_pneumonia cp
  LEFT JOIN icu_flags icu ON cp.hadm_id = icu.hadm_id
  LEFT JOIN comorb_counts com ON cp.hadm_id = com.hadm_id
),
base_metrics AS (
  SELECT pneumonia_type, los_cat, icu_day1,
         COUNT(*) AS n,
         SUM(hospital_expire_flag) AS deaths,
         ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
         AVG(comorb_count) AS avg_comorb
  FROM main_data
  GROUP BY pneumonia_type, los_cat, icu_day1
)
SELECT 
  los_cat,
  CASE WHEN icu_day1 = 1 THEN 'Yes' ELSE 'No' END AS icu_day1_status,
  MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN n END) AS n_asp,
  MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN deaths END) AS deaths_asp,
  MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN mortality_pct END) AS mort_asp_pct,
  MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN avg_comorb END) AS avg_comorb_asp,
  MAX(CASE WHEN pneumonia_type = 'Community-acquired' THEN n END) AS n_comm,
  MAX(CASE WHEN pneumonia_type = 'Community-acquired' THEN deaths END) AS deaths_comm,
  MAX(CASE WHEN pneumonia_type = 'Community-acquired' THEN mortality_pct END) AS mort_comm_pct,
  MAX(CASE WHEN pneumonia_type = 'Community-acquired' THEN avg_comorb END) AS avg_comorb_comm,
  (MAX(CASE WHEN pneumonia_type = 'Community-acquired' THEN mortality_pct END) -
   MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN mortality_pct END)) AS abs_diff_pct,
  CASE WHEN MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN n END) > 0 
            AND MAX(CASE WHEN pneumonia_type = 'Community-acquired' THEN n END) > 0
            AND MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN mortality_pct END) > 0
       THEN ROUND(
         (MAX(CASE WHEN pneumonia_type = 'Community-acquired' THEN mortality_pct END) -
          MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN mortality_pct END)) /
         MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN mortality_pct END) * 100, 2)
       ELSE NULL END AS rel_diff_pct
FROM base_metrics
GROUP BY los_cat, icu_day1
ORDER BY los_cat, icu_day1_status;
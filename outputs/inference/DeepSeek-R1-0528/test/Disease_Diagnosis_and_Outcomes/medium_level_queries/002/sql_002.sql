WITH base_cohort AS (
  SELECT 
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
      -- Comorbidity flags
      MAX(CASE 
          WHEN d.icd_version = 9 AND d.icd_code IN ('585','5851','5852','5853','5854','5855','5856','5859','586','40301','40311','40391','40402','40403','40412','40413','40492','40493') THEN 1
          WHEN d.icd_version = 10 AND d.icd_code IN ('N181','N182','N183','N184','N185','N186','N189','N180','I120','I130','I1310','I1311','I132') THEN 1
          ELSE 0 
      END) AS ckd_flag,
      MAX(CASE 
          WHEN d.icd_version = 9 AND d.icd_code LIKE '250%' THEN 1
          WHEN d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%') THEN 1
          ELSE 0 
      END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
      p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 62 AND 72
      AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%') OR  -- AMI ICD-9
          (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))  -- AMI ICD-10
      )
      AND a.hadm_id NOT IN (  -- Exclude shock/respiratory failure
          SELECT hadm_id 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
          WHERE 
              (icd_version = 9 AND (icd_code LIKE '785.5%' OR icd_code LIKE '998.0%' OR icd_code IN ('51881','51882','51884','51885'))) OR
              (icd_version = 10 AND (icd_code LIKE 'R57%' OR icd_code LIKE 'T81.1%' OR icd_code LIKE 'J96%'))
      )
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
group_stats AS (  -- Renamed from 'groups' (reserved keyword)
  SELECT 
      CASE WHEN los_days <= 5 THEN 'LOS ≤5' ELSE 'LOS >5' END AS los_group,
      COUNT(*) AS total_patients,
      SUM(hospital_expire_flag) AS deaths,
      SUM(ckd_flag) AS ckd_count,
      SUM(diabetes_flag) AS diabetes_count
  FROM base_cohort
  GROUP BY los_group
),
group_rates AS (
  SELECT 
      los_group,
      total_patients,
      deaths,
      ROUND(deaths * 100.0 / total_patients, 2) AS mortality_rate,
      ROUND(ckd_count * 100.0 / total_patients, 2) AS ckd_prevalence,
      ROUND(diabetes_count * 100.0 / total_patients, 2) AS diabetes_prevalence
  FROM group_stats  -- Reference updated
),
pivoted_mortality AS (
  SELECT
      MAX(CASE WHEN los_group = 'LOS ≤5' THEN mortality_rate END) AS mort_rate_short,
      MAX(CASE WHEN los_group = 'LOS >5' THEN mortality_rate END) AS mort_rate_long
  FROM group_rates
)
SELECT 
    los_group AS group_label,
    total_patients,
    deaths,
    mortality_rate,
    ckd_prevalence,
    diabetes_prevalence,
    NULL AS absolute_difference,
    NULL AS relative_difference
FROM group_rates
UNION ALL
SELECT 
    'Mortality Comparison' AS group_label,
    NULL AS total_patients,
    NULL AS deaths,
    NULL AS mortality_rate,
    NULL AS ckd_prevalence,
    NULL AS diabetes_prevalence,
    (SELECT mort_rate_long - mort_rate_short FROM pivoted_mortality) AS absolute_difference,
    ROUND(SAFE_DIVIDE((SELECT mort_rate_long - mort_rate_short FROM pivoted_mortality), 
                      (SELECT mort_rate_short FROM pivoted_mortality)) * 100, 2) AS relative_difference;
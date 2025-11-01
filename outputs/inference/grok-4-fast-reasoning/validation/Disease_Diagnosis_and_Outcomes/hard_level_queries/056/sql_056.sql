WITH base_patients AS (
  SELECT subject_id, anchor_age, gender, dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 63 AND 73
),
base_admissions AS (
  SELECT a.*, p.dod, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN base_patients p ON a.subject_id = p.subject_id
),
all_admissions AS (
  SELECT a.*, p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
),
num_diagnoses AS (
  SELECT subject_id, hadm_id, COUNT(*) AS num_dx
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
has_septic_shock AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '785.52')
     OR (icd_version = 10 AND icd_code = 'R65.21')
),
drg_mortality AS (
  SELECT subject_id, hadm_id, AVG(drg_mortality) AS drg_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  WHERE drg_type = 'MS'
  GROUP BY subject_id, hadm_id
),
has_procedure AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
),
cohort AS (
  SELECT 
    ba.hadm_id, ba.subject_id, ba.admittime, ba.dischtime, ba.hospital_expire_flag, ba.dod,
    COALESCE(nd.num_dx, 0) AS num_dx,
    CASE WHEN hss.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ss,
    dm.drg_mortality,
    CASE WHEN hp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_comp
  FROM base_admissions ba
  LEFT JOIN num_diagnoses nd ON ba.subject_id = nd.subject_id AND ba.hadm_id = nd.hadm_id
  LEFT JOIN has_septic_shock hss ON ba.subject_id = hss.subject_id AND ba.hadm_id = hss.hadm_id
  LEFT JOIN drg_mortality dm ON ba.subject_id = dm.subject_id AND ba.hadm_id = dm.hadm_id
  LEFT JOIN has_procedure hp ON ba.subject_id = hp.subject_id AND ba.hadm_id = hp.hadm_id
  WHERE COALESCE(nd.num_dx, 0) > 15 AND hss.hadm_id IS NOT NULL
),
general_all AS (
  SELECT 
    aa.hadm_id, aa.subject_id, aa.admittime, aa.dischtime, aa.hospital_expire_flag, aa.dod,
    COALESCE(nd.num_dx, 0) AS num_dx,
    CASE WHEN hss.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ss,
    dm.drg_mortality,
    CASE WHEN hp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_comp
  FROM all_admissions aa
  LEFT JOIN num_diagnoses nd ON aa.subject_id = nd.subject_id AND aa.hadm_id = nd.hadm_id
  LEFT JOIN has_septic_shock hss ON aa.subject_id = hss.subject_id AND aa.hadm_id = hss.hadm_id
  LEFT JOIN drg_mortality dm ON aa.subject_id = dm.subject_id AND aa.hadm_id = dm.hadm_id
  LEFT JOIN has_procedure hp ON aa.subject_id = hp.subject_id AND aa.hadm_id = hp.hadm_id
),
general AS (
  SELECT * FROM general_all
),
profile_numdx AS (
  SELECT COALESCE(nd.num_dx, 0) AS num_dx
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN num_diagnoses nd ON a.subject_id = nd.subject_id AND a.hadm_id = nd.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age = 68
),
cohort_stats AS (
  SELECT 
    'cohort' AS group_type,
    AVG(drg_mortality) AS mean_risk_score,
    AVG(CASE 
      WHEN dod IS NOT NULL 
        AND DATE(dod) >= DATE(admittime) 
        AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 
      THEN 1.0 
      ELSE 0.0 
    END) AS mortality_90d_rate,
    AVG(CASE WHEN has_comp = 1 THEN 1.0 ELSE 0.0 END) AS major_comp_rate,
    AVG(CASE 
      WHEN hospital_expire_flag = 0 
      THEN TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 
      ELSE NULL 
    END) AS survivor_los,
    NULL AS percentile
  FROM cohort
),
general_stats AS (
  SELECT 
    'general' AS group_type,
    AVG(drg_mortality) AS mean_risk_score,
    AVG(CASE 
      WHEN dod IS NOT NULL 
        AND DATE(dod) >= DATE(admittime) 
        AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 
      THEN 1.0 
      ELSE 0.0 
    END) AS mortality_90d_rate,
    AVG(CASE WHEN has_comp = 1 THEN 1.0 ELSE 0.0 END) AS major_comp_rate,
    AVG(CASE 
      WHEN hospital_expire_flag = 0 
      THEN TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 
      ELSE NULL 
    END) AS survivor_los,
    NULL AS percentile
  FROM general
),
profile_percentile AS (
  SELECT 
    'profile_68M_16dx' AS group_type,
    NULL AS mean_risk_score,
    NULL AS mortality_90d_rate,
    NULL AS major_comp_rate,
    NULL AS survivor_los,
    COUNTIF(num_dx <= 16) * 100.0 / COUNT(*) AS percentile
  FROM profile_numdx
)
SELECT group_type, mean_risk_score, mortality_90d_rate, major_comp_rate, survivor_los, percentile
FROM cohort_stats
UNION ALL
SELECT group_type, mean_risk_score, mortality_90d_rate, major_comp_rate, survivor_los, percentile
FROM general_stats
UNION ALL
SELECT group_type, mean_risk_score, mortality_90d_rate, major_comp_rate, survivor_los, percentile
FROM profile_percentile;
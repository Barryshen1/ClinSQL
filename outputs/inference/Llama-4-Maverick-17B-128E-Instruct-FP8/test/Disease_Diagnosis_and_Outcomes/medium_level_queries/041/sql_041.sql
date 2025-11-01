WITH 
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 50 AND 60
),
admissions_filtered AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
),
sepsis_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Sepsis%' AND dicd.long_title NOT LIKE '%septic shock%'
),
combined_data AS (
  SELECT 
    af.hadm_id,
    af.admittime,
    af.dischtime,
    af.deathtime,
    DATETIME_DIFF(af.dischtime, af.admittime, DAY) AS los,
    CASE WHEN af.deathtime IS NOT NULL AND af.deathtime <= af.dischtime THEN 1 ELSE 0 END AS in_hospital_mortality,
    DATETIME_DIFF(af.deathtime, af.admittime, DAY) AS time_to_death
  FROM admissions_filtered af
  INNER JOIN sepsis_patients sp ON af.hadm_id = sp.hadm_id
),
stats AS (
  SELECT 
    CASE WHEN los <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END AS los_category,
    COUNT(*) AS total_patients,
    SUM(in_hospital_mortality) AS deaths,
    AVG(in_hospital_mortality) * 100 AS mortality_percentage
  FROM combined_data
  GROUP BY CASE WHEN los <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END
),
mortality_diff AS (
  SELECT 
    (SELECT mortality_percentage FROM stats WHERE los_category = 'LOS > 7') - (SELECT mortality_percentage FROM stats WHERE los_category = 'LOS <= 7') AS absolute_diff,
    ((SELECT mortality_percentage FROM stats WHERE los_category = 'LOS > 7') - (SELECT mortality_percentage FROM stats WHERE los_category = 'LOS <= 7')) / (SELECT mortality_percentage FROM stats WHERE los_category = 'LOS <= 7') * 100 AS relative_diff
),
time_to_death_median AS (
  SELECT APPROX_QUANTILES(time_to_death, 100)[OFFSET(50)] AS median_time_to_death
  FROM combined_data
  WHERE in_hospital_mortality = 1
)
SELECT 
  s.los_category,
  s.total_patients,
  s.deaths,
  s.mortality_percentage,
  md.absolute_diff,
  md.relative_diff,
  ttd.median_time_to_death
FROM stats s
CROSS JOIN mortality_diff md
CROSS JOIN time_to_death_median ttd;
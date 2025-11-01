WITH patients_44_male AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age = 44 AND gender = 'M'
),
postoperative_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
  WHERE EXISTS (
    SELECT 1
    FROM patients_44_male p44
    WHERE p44.subject_id = a.subject_id
  )
),
icu_flag AS (
  SELECT 
    a.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_group
  FROM postoperative_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),
los_groups AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 3 THEN '≤3'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 6 THEN '4-6'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10' 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM postoperative_admissions)
),
charlson_mapping AS (
  SELECT 'A41.9' AS icd_code, 6 AS weight, 'Sepsis' AS condition_group
  UNION ALL SELECT 'I21.9', 1, 'Myocardial infarction'
  UNION ALL SELECT 'I50.9', 1, 'Congestive heart failure'
  UNION ALL SELECT 'I10', 1, 'Hypertension'
  UNION ALL SELECT 'E11.9', 1, 'Diabetes without complications'
  UNION ALL SELECT 'E11.20', 2, 'Diabetes with complications'
  -- Add comprehensive ICD-10 mappings here
),
charlson_per_admission AS (
  SELECT 
    d.hadm_id,
    SUM(DISTINCT c.weight) AS charlson_index
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN charlson_mapping c 
    ON d.icd_code = c.icd_code AND d.icd_version = 10
  WHERE d.hadm_id IN (SELECT hadm_id FROM postoperative_admissions)
  GROUP BY d.hadm_id
),
mechanical_ventilation AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN itemid = 223835 AND valuenum = 1 THEN 1 ELSE 0 END) AS mech_vent
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE hadm_id IN (SELECT hadm_id FROM icu_flag WHERE icu_group = 'ICU')
  GROUP BY hadm_id
  UNION ALL
  SELECT 
    hadm_id,
    MAX(CASE WHEN medication LIKE '%mechanical ventilation%' THEN 1 ELSE 0 END) AS mech_vent
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE hadm_id IN (SELECT hadm_id FROM icu_flag WHERE icu_group = 'non-ICU')
  GROUP BY hadm_id
),
vasopressors AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN itemid IN (221662, 221663) THEN 1 ELSE 0 END) AS vasopressor
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE hadm_id IN (SELECT hadm_id FROM icu_flag WHERE icu_group = 'ICU')
  GROUP BY hadm_id
  UNION ALL
  SELECT 
    hadm_id,
    MAX(CASE WHEN drug IN ('norepinephrine', 'epinephrine') THEN 1 ELSE 0 END) AS vasopressor
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM icu_flag WHERE icu_group = 'non-ICU')
  GROUP BY hadm_id
),
rrt AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code IN ('Z99.2', 'Z49.0') THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM postoperative_admissions)
  GROUP BY hadm_id
),
main_cohort AS (
  SELECT 
    i.icu_group,
    l.los_group,
    CASE 
      WHEN c.charlson_index <= 3 THEN '≤3'
      WHEN c.charlson_index BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5' 
    END AS charlson_group,
    a.hospital_expire_flag AS mortality,
    COALESCE(m.mech_vent, 0) AS mech_vent,
    COALESCE(v.vasopressor, 0) AS vasopressor,
    COALESCE(r.rrt, 0) AS rrt
  FROM postoperative_admissions p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.hadm_id = a.hadm_id
  JOIN icu_flag i ON p.hadm_id = i.hadm_id
  JOIN los_groups l ON p.hadm_id = l.hadm_id
  LEFT JOIN charlson_per_admission c ON p.hadm_id = c.hadm_id
  LEFT JOIN mechanical_ventilation m ON p.hadm_id = m.hadm_id
  LEFT JOIN vasopressors v ON p.hadm_id = v.hadm_id
  LEFT JOIN rrt r ON p.hadm_id = r.hadm_id
),
averages_by_group AS (
  SELECT 
    icu_group,
    charlson_group,
    los_group,
    AVG(mech_vent) AS mech_vent_avg,
    AVG(vasopressor) AS vasopressor_avg,
    AVG(rrt) AS rrt_avg
  FROM main_cohort
  GROUP BY icu_group, charlson_group, los_group
),
mortality_by_group AS (
  SELECT 
    icu_group,
    charlson_group,
    los_group,
    AVG(mortality) AS mortality_rate
  FROM main_cohort
  GROUP BY icu_group, charlson_group, los_group
),
mortality_le3 AS (
  SELECT 
    icu_group,
    charlson_group,
    mortality_rate AS mortality_rate_le3
  FROM mortality_by_group
  WHERE los_group = '≤3'
)
SELECT 
  m.icu_group,
  m.charlson_group,
  m.los_group,
  m.mortality_rate * 100 AS mortality_percent,
  (m.mortality_rate - COALESCE(ml.mortality_rate_le3, 0)) * 100 AS abs_diff,
  (m.mortality_rate - COALESCE(ml.mortality_rate_le3, 0)) / NULLIF(ml.mortality_rate_le3, 0) AS rel_diff,
  a.mech_vent_avg * 100 AS mech_vent_percent,
  a.vasopressor_avg * 100 AS vasopressors_percent,
  a.rrt_avg * 100 AS rrt_percent
FROM mortality_by_group m
LEFT JOIN mortality_le3 ml 
  ON m.icu_group = ml.icu_group AND m.charlson_group = ml.charlson_group
JOIN averages_by_group a 
  ON m.icu_group = a.icu_group 
  AND m.charlson_group = a.charlson_group 
  AND m.los_group = a.los_group
ORDER BY 
  m.icu_group, 
  m.charlson_group, 
  m.los_group;
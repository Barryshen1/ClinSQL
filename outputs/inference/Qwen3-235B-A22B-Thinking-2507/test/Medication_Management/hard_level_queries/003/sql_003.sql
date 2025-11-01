WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 39 AND 49
),
drug_exposure AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    p.drug,
    p.starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime >= c.admittime
    AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
drug_classification AS (
  SELECT 
    subject_id,
    hadm_id,
    drug,
    CASE 
      WHEN LOWER(drug) LIKE '%amiodarone%' OR 
           LOWER(drug) LIKE '%sotalol%' OR 
           LOWER(drug) LIKE '%haloperidol%' OR
           LOWER(drug) LIKE '%methadone%' OR
           LOWER(drug) LIKE '%ciprofloxacin%' OR
           LOWER(drug) LIKE '%levofloxacin%' OR
           LOWER(drug) LIKE '%moxifloxacin%'
      THEN 1 
      ELSE 0 
    END AS is_qt_drug,
    CASE 
      WHEN LOWER(drug) LIKE '%warfarin%' OR 
           LOWER(drug) LIKE '%heparin%' OR 
           LOWER(drug) LIKE '%aspirin%' OR
           LOWER(drug) LIKE '%clopidogrel%' OR
           LOWER(drug) LIKE '%rivaroxaban%' OR
           LOWER(drug) LIKE '%apixaban%' OR
           LOWER(drug) LIKE '%dabigatran%'
      THEN 1 
      ELSE 0 
    END AS is_bleeding_drug
  FROM drug_exposure
),
patient_drug_summary AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS num_drugs,
    MAX(is_qt_drug) AS is_qt,
    MAX(is_bleeding_drug) AS is_bleeding
  FROM drug_classification
  GROUP BY subject_id, hadm_id
),
cohort_with_drugs AS (
  SELECT 
    c.*,
    COALESCE(pds.num_drugs, 0) AS num_drugs,
    COALESCE(pds.is_qt, 0) AS is_qt,
    COALESCE(pds.is_bleeding, 0) AS is_bleeding
  FROM cohort c
  LEFT JOIN patient_drug_summary pds
    ON c.subject_id = pds.subject_id AND c.hadm_id = pds.hadm_id
),
cohort_with_percentile AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY num_drugs) AS percentile_rank
  FROM cohort_with_drugs
),
group_membership AS (
  SELECT subject_id, hadm_id, num_drugs, percentile_rank, los_days, hospital_expire_flag, 'All' AS group_type
  FROM cohort_with_percentile
  UNION ALL
  SELECT subject_id, hadm_id, num_drugs, percentile_rank, los_days, hospital_expire_flag, 'QT'
  FROM cohort_with_percentile
  WHERE is_qt = 1
  UNION ALL
  SELECT subject_id, hadm_id, num_drugs, percentile_rank, los_days, hospital_expire_flag, 'Bleeding'
  FROM cohort_with_percentile
  WHERE is_bleeding = 1
),
group_aggregates AS (
  SELECT
    group_type,
    COUNT(*) AS num_patients,
    AVG(num_drugs) AS avg_num_drugs,
    AVG(percentile_rank) AS avg_percentile_rank,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM group_membership
  GROUP BY group_type
),
qt_group AS (
  SELECT *
  FROM cohort_with_percentile
  WHERE is_qt = 1
),
bleeding_group AS (
  SELECT *
  FROM cohort_with_percentile
  WHERE is_bleeding = 1
),
qt_top_quartile AS (
  SELECT *
  FROM qt_group
  WHERE num_drugs >= (
    SELECT APPROX_QUANTILES(num_drugs, 100)[OFFSET(75)]
    FROM qt_group
  )
),
bleeding_top_quartile AS (
  SELECT *
  FROM bleeding_group
  WHERE num_drugs >= (
    SELECT APPROX_QUANTILES(num_drugs, 100)[OFFSET(75)]
    FROM bleeding_group
  )
),
top_quartile_aggregates AS (
  SELECT 'QT_top25' AS group_type, 
         COUNT(*) AS num_patients,
         AVG(num_drugs) AS avg_num_drugs,
         AVG(percentile_rank) AS avg_percentile_rank,
         AVG(los_days) AS avg_los,
         AVG(hospital_expire_flag) AS mortality_rate
  FROM qt_top_quartile
  UNION ALL
  SELECT 'Bleeding_top25' AS group_type, 
         COUNT(*) AS num_patients,
         AVG(num_drugs) AS avg_num_drugs,
         AVG(percentile_rank) AS avg_percentile_rank,
         AVG(los_days) AS avg_los,
         AVG(hospital_expire_flag) AS mortality_rate
  FROM bleeding_top_quartile
)
SELECT * FROM group_aggregates
UNION ALL
SELECT * FROM top_quartile_aggregates;
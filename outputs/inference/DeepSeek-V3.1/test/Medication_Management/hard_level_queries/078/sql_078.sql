WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),

meds AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count,
    COUNT(DISTINCT CASE 
      WHEN LOWER(pr.drug) LIKE '%amiodarone%' OR 
           LOWER(pr.drug) LIKE '%sotalol%' OR 
           LOWER(pr.drug) LIKE '%quinidine%' OR 
           LOWER(pr.drug) LIKE '%disopyramide%' OR 
           LOWER(pr.drug) LIKE '%dofetilide%' OR 
           LOWER(pr.drug) LIKE '%ibutilide%' OR 
           LOWER(pr.drug) LIKE '%procainamide%' OR 
           LOWER(pr.drug) LIKE '%azithromycin%' OR 
           LOWER(pr.drug) LIKE '%erythromycin%' OR 
           LOWER(pr.drug) LIKE '%clarithromycin%' OR 
           LOWER(pr.drug) LIKE '%ciprofloxacin%' OR 
           LOWER(pr.drug) LIKE '%levofloxacin%' OR 
           LOWER(pr.drug) LIKE '%moxifloxacin%' OR 
           LOWER(pr.drug) LIKE '%ondansetron%' OR 
           LOWER(pr.drug) LIKE '%domperidone%' OR 
           LOWER(pr.drug) LIKE '%droperidol%' OR 
           LOWER(pr.drug) LIKE '%haloperidol%' OR 
           LOWER(pr.drug) LIKE '%methadone%' OR 
           LOWER(pr.drug) LIKE '%pentamidine%' OR 
           LOWER(pr.drug) LIKE '%arsenic%' OR 
           LOWER(pr.drug) LIKE '%citalopram%' OR 
           LOWER(pr.drug) LIKE '%escitalopram%' OR 
           LOWER(pr.drug) LIKE '%chlorpromazine%' OR 
           LOWER(pr.drug) LIKE '%thioridazine%' OR 
           LOWER(pr.drug) LIKE '%ziprasidone%'
      THEN pr.drug 
    END) AS qt_drug_count,
    COUNT(DISTINCT CASE 
      WHEN LOWER(pr.drug) LIKE '%warfarin%' OR 
           LOWER(pr.drug) LIKE '%heparin%' OR 
           LOWER(pr.drug) LIKE '%enoxaparin%' OR 
           LOWER(pr.drug) LIKE '%dalteparin%' OR 
           LOWER(pr.drug) LIKE '%clopidogrel%' OR 
           LOWER(pr.drug) LIKE '%ticagrelor%' OR 
           LOWER(pr.drug) LIKE '%prasugrel%' OR 
           LOWER(pr.drug) LIKE '%aspirin%' OR 
           LOWER(pr.drug) LIKE '%dabigatran%' OR 
           LOWER(pr.drug) LIKE '%rivaroxaban%' OR 
           LOWER(pr.drug) LIKE '%apixaban%' OR 
           LOWER(pr.drug) LIKE '%edoxaban%' OR 
           LOWER(pr.drug) LIKE '%ticlopidine%' OR 
           LOWER(pr.drug) LIKE '%dipyridamole%'
      THEN pr.drug 
    END) AS bleeding_drug_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
),

meds_with_percentile AS (
  SELECT 
    hadm_id,
    med_count,
    qt_drug_count,
    bleeding_drug_count,
    PERCENT_RANK() OVER (ORDER BY med_count) AS complexity_percentile
  FROM meds
),

icu_flag AS (
  SELECT 
    c.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu_stay
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
)

SELECT 
  'All cohort' AS group,
  COUNT(*) AS n_patients,
  AVG(med_count) AS mean_complexity,
  MIN(med_count) AS min_complexity,
  MAX(med_count) AS max_complexity,
  STDDEV(med_count) AS sd_complexity,
  AVG(complexity_percentile) AS mean_complexity_percentile,
  AVG(CASE WHEN qt_drug_count > 0 THEN 1 ELSE 0 END) AS qt_drug_prevalence,
  AVG(CASE WHEN bleeding_drug_count > 0 THEN 1 ELSE 0 END) AS bleeding_drug_prevalence,
  NULL AS mean_los,
  NULL AS mortality_rate
FROM meds_with_percentile m
INNER JOIN cohort c ON m.hadm_id = c.hadm_id

UNION ALL

SELECT 
  'ICU' AS group,
  COUNT(*) AS n_patients,
  AVG(med_count) AS mean_complexity,
  MIN(med_count) AS min_complexity,
  MAX(med_count) AS max_complexity,
  STDDEV(med_count) AS sd_complexity,
  AVG(complexity_percentile) AS mean_complexity_percentile,
  AVG(CASE WHEN qt_drug_count > 0 THEN 1 ELSE 0 END) AS qt_drug_prevalence,
  AVG(CASE WHEN bleeding_drug_count > 0 THEN 1 ELSE 0 END) AS bleeding_drug_prevalence,
  NULL AS mean_los,
  NULL AS mortality_rate
FROM meds_with_percentile m
INNER JOIN cohort c ON m.hadm_id = c.hadm_id
INNER JOIN icu_flag i ON c.hadm_id = i.hadm_id
WHERE i.had_icu_stay = 1

UNION ALL

SELECT 
  'Non-ICU' AS group,
  COUNT(*) AS n_patients,
  AVG(med_count) AS mean_complexity,
  MIN(med_count) AS min_complexity,
  MAX(med_count) AS max_complexity,
  STDDEV(med_count) AS sd_complexity,
  AVG(complexity_percentile) AS mean_complexity_percentile,
  AVG(CASE WHEN qt_drug_count > 0 THEN 1 ELSE 0 END) AS qt_drug_prevalence,
  AVG(CASE WHEN bleeding_drug_count > 0 THEN 1 ELSE 0 END) AS bleeding_drug_prevalence,
  NULL AS mean_los,
  NULL AS mortality_rate
FROM meds_with_percentile m
INNER JOIN cohort c ON m.hadm_id = c.hadm_id
INNER JOIN icu_flag i ON c.hadm_id = i.hadm_id
WHERE i.had_icu_stay = 0

UNION ALL

SELECT 
  'Top quartile complexity' AS group,
  COUNT(*) AS n_patients,
  NULL AS mean_complexity,
  NULL AS min_complexity,
  NULL AS max_complexity,
  NULL AS sd_complexity,
  NULL AS mean_complexity_percentile,
  NULL AS qt_drug_prevalence,
  NULL AS bleeding_drug_prevalence,
  AVG(DATE_DIFF(c.dischtime, c.admittime, DAY)) AS mean_los,
  AVG(c.hospital_expire_flag) AS mortality_rate
FROM meds_with_percentile m
INNER JOIN cohort c ON m.hadm_id = c.hadm_id
WHERE complexity_percentile >= 0.75;
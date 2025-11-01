WITH subgroup_hadms AS (
  -- Female, 68-78yo with HHS diagnosis
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '250.2%')  -- ICD-9 HHS
      OR 
      (d.icd_version = 10 AND d.icd_code IN ('E11.00', 'E11.01', 'E13.00', 'E13.01'))  -- ICD-10 HHS (with/without coma)
    )
),
all_hadms AS (
  -- All hospital admissions
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cohort_hadms AS (
  -- Assign cohorts
  SELECT hadm_id, 'HHS_female_68-78' AS cohort FROM subgroup_hadms
  UNION ALL
  SELECT hadm_id, 'all' AS cohort FROM all_hadms
),
med_counts AS (
  -- Unique meds in first 72h
  SELECT pr.hadm_id, COUNT(DISTINCT LOWER(pr.drug)) AS num_meds
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE pr.starttime >= a.admittime
    AND pr.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 3 DAY)
  GROUP BY pr.hadm_id
),
interaction_flags AS (
  -- Hyperkalemia-risk flags in first 72h
  SELECT pr.hadm_id,
         MAX(CASE WHEN LOWER(pr.drug) LIKE '%potassium%' THEN 1 ELSE 0 END) AS has_potassium,
         MAX(CASE WHEN LOWER(pr.drug) IN (
           'lisinopril', 'enalapril', 'captopril', 'ramipril', 'fosinopril', 'quinapril',
           'benazepril', 'moexipril', 'perindopril', 'trandolapril',
           'losartan', 'valsartan', 'irbesartan', 'candesartan', 'telmisartan',
           'olmesartan', 'azilsartan', 'spironolactone', 'eplerenone'
         ) THEN 1 ELSE 0 END) AS has_raas
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE pr.starttime >= a.admittime
    AND pr.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 3 DAY)
  GROUP BY pr.hadm_id
),
los_mort AS (
  -- Base with LOS, mortality, interactions
  SELECT
    ch.cohort,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    CASE
      WHEN COALESCE(ifp.has_potassium, 0) = 1 AND COALESCE(ifp.has_raas, 0) = 1 THEN 1
      ELSE 0
    END AS has_interaction
  FROM cohort_hadms ch
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ch.hadm_id = a.hadm_id
  LEFT JOIN interaction_flags ifp
    ON a.hadm_id = ifp.hadm_id
  WHERE a.dischtime IS NOT NULL  -- Complete admissions only
),
all_los_ranked AS (
  -- LOS percentile ranks over ALL inpatients
  SELECT hadm_id,
         PERCENT_RANK() OVER (ORDER BY los) AS los_percentile
  FROM los_mort
  WHERE cohort = 'all'
),
los_mort_with_rank AS (
  -- Add ranks to all rows (for affected patients)
  SELECT lm.*, alr.los_percentile
  FROM los_mort lm
  LEFT JOIN all_los_ranked alr
    ON lm.hadm_id = alr.hadm_id
),
summary_los_mort AS (
  -- LOS/mortality summaries
  SELECT
    cohort,
    PERCENTILE_CONT(los, 0.75) AS top_quartile_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM los_mort_with_rank
  GROUP BY cohort
),
summary_percent_affected AS (
  -- % affected
  SELECT
    cohort,
    AVG(has_interaction) AS percent_affected
  FROM los_mort_with_rank
  GROUP BY cohort
),
summary_median_rank AS (
  -- Median percentile rank for affected patients
  SELECT
    cohort,
    PERCENTILE_CONT(los_percentile, 0.5) AS median_percentile_rank_affected
  FROM los_mort_with_rank
  WHERE has_interaction = 1
  GROUP BY cohort
),
med_dist AS (
  -- Medication complexity distribution
  SELECT
    ch.cohort,
    COALESCE(mc.num_meds, 0) AS num_meds,
    COUNT(*) AS patient_count
  FROM cohort_hadms ch
  LEFT JOIN med_counts mc
    ON ch.hadm_id = mc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a  -- Ensure valid admission
    ON ch.hadm_id = a.hadm_id
  WHERE a.dischtime IS NOT NULL
  GROUP BY ch.cohort, COALESCE(mc.num_meds, 0)
  ORDER BY ch.cohort, num_meds
),
combined_scalars AS (
  -- Combine all scalar metrics into rows
  SELECT cohort, 'top_quartile_los' AS metric, CAST(top_quartile_los AS STRING) AS value
  FROM summary_los_mort
  UNION ALL
  SELECT cohort, 'mortality_rate' AS metric, CAST(mortality_rate AS STRING)
  FROM summary_los_mort
  UNION ALL
  SELECT cohort, 'percent_affected' AS metric, CAST(percent_affected AS STRING)
  FROM summary_percent_affected
  UNION ALL
  SELECT cohort, 'median_percentile_rank_affected' AS metric, CAST(median_percentile_rank_affected AS STRING)
  FROM summary_median_rank
)
-- Output scalar metrics
SELECT * FROM combined_scalars
ORDER BY cohort, metric

-- Output medication complexity distribution
SELECT * FROM med_dist;
WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
multi_trauma_admissions AS (
  SELECT da.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON da.icd_code = d.icd_code AND da.icd_version = d.icd_version
  WHERE da.icd_version = 10
    AND SUBSTR(d.icd_code, 1, 1) IN ('S', 'T')
  GROUP BY da.hadm_id
  HAVING COUNT(*) >= 2
),
first_24h_prescriptions AS (
  SELECT pr.hadm_id, pr.drug, pr.starttime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON pr.hadm_id = a.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= a.admittime
    AND pr.starttime < DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
),
medication_counts AS (
  SELECT 
    f.hadm_id,
    COUNT(*) AS med_count
  FROM first_24h_prescriptions f
  GROUP BY f.hadm_id
),
serotonergic_drugs AS (
  SELECT DISTINCT hadm_id
  FROM first_24h_prescriptions
  WHERE LOWER(drug) IN (
    'sertraline', 'citalopram', 'escitalopram', 'fluoxetine', 'paroxetine',
    'venlafaxine', 'duloxetine', 'milnacipran', 'tramadol', 'fentanyl',
    'ondansetron', 'granisetron', 'dolasetron', 'palonosetron',
    'sumatriptan', 'rizatriptan', 'zolmitriptan', 'eletriptan',
    'dextromethorphan', 'bupropion', 'trazodone', 'amitriptyline',
    'imipramine', 'nortriptyline', 'clomipramine', 'linezolid',
    'lithium', 'fentanyl', 'meperidine', 'pentazocine', 'propoxyphene'
  )
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    mc.med_count,
    CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_serotonergic,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  INNER JOIN multi_trauma_admissions mta ON a.hadm_id = mta.hadm_id
  INNER JOIN medication_counts mc ON a.hadm_id = mc.hadm_id
  LEFT JOIN serotonergic_drugs sd ON a.hadm_id = sd.hadm_id
),
ranked AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY med_count) AS complexity_percentile,
    NTILE(4) OVER (ORDER BY med_count) AS complexity_quartile
  FROM cohort
)
SELECT
  'All' as analysis_group,
  has_serotonergic,
  complexity_quartile,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM ranked
GROUP BY has_serotonergic, complexity_quartile

UNION ALL

SELECT
  'Top Quartile Only' as analysis_group,
  has_serotonergic,
  complexity_quartile,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM ranked
WHERE complexity_quartile = 4
GROUP BY has_serotonergic, complexity_quartile

ORDER BY analysis_group, has_serotonergic, complexity_quartile;
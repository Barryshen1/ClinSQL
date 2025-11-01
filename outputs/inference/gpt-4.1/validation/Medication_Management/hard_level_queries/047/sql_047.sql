WITH cohort AS (
  -- Select female inpatients aged 48-58 at admission, first qualifying admission
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    -- Calculate age at admission
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
),
stroke_cases AS (
  -- Identify hemorrhagic stroke cases
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10: I60-I62
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I6[0-2]'))
      -- ICD-9: 430-432
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^43[0-2]'))
    )
),
controls AS (
  -- Controls: cohort minus stroke cases
  SELECT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
  WHERE
    NOT EXISTS (
      SELECT 1 FROM stroke_cases sc WHERE sc.subject_id = c.subject_id AND sc.hadm_id = c.hadm_id
    )
),
first_admission AS (
  -- For each subject, select their first qualifying admission (cases and controls)
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM
    cohort
  GROUP BY subject_id
),
study_cohort AS (
  -- Restrict to first qualifying admission per subject
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.gender,
    c.age_at_admit,
    CASE WHEN sc.subject_id IS NOT NULL THEN 'stroke' ELSE 'control' END AS group_type
  FROM
    cohort c
    LEFT JOIN stroke_cases sc
      ON c.subject_id = sc.subject_id AND c.hadm_id = sc.hadm_id
    JOIN first_admission fa
      ON c.subject_id = fa.subject_id AND c.admittime = fa.first_admittime
),
meds_48h AS (
  -- Get all unique drugs administered/ordered in first 48h for each admission
  SELECT
    s.subject_id,
    s.hadm_id,
    LOWER(TRIM(pr.drug)) AS drug_name
  FROM
    study_cohort s
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON s.subject_id = pr.subject_id AND s.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= s.admittime
    AND pr.starttime < DATETIME_ADD(s.admittime, INTERVAL 48 HOUR)
    AND pr.drug IS NOT NULL
  UNION DISTINCT
  SELECT
    s.subject_id,
    s.hadm_id,
    LOWER(TRIM(em.medication)) AS drug_name
  FROM
    study_cohort s
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
      ON s.subject_id = em.subject_id AND s.hadm_id = em.hadm_id
  WHERE
    em.charttime >= s.admittime
    AND em.charttime < DATETIME_ADD(s.admittime, INTERVAL 48 HOUR)
    AND em.medication IS NOT NULL
),
serotonergic_drugs AS (
  -- List of serotonergic drugs (lowercase for matching)
  SELECT 'sertraline' AS drug UNION ALL
  SELECT 'fluoxetine' UNION ALL
  SELECT 'paroxetine' UNION ALL
  SELECT 'citalopram' UNION ALL
  SELECT 'escitalopram' UNION ALL
  SELECT 'venlafaxine' UNION ALL
  SELECT 'duloxetine' UNION ALL
  SELECT 'trazodone' UNION ALL
  SELECT 'bupropion' UNION ALL
  SELECT 'mirtazapine' UNION ALL
  SELECT 'tramadol' UNION ALL
  SELECT 'linezolid' UNION ALL
  SELECT 'sumatriptan' UNION ALL
  SELECT 'zolmitriptan' UNION ALL
  SELECT 'fentanyl' UNION ALL
  SELECT 'methadone' UNION ALL
  SELECT 'meperidine' UNION ALL
  SELECT 'buspirone' UNION ALL
  SELECT 'ondansetron' UNION ALL
  SELECT 'granisetron' UNION ALL
  SELECT 'dextromethorphan' UNION ALL
  SELECT 'lithium' UNION ALL
  SELECT 'mdma' UNION ALL
  SELECT 'st. john'
),
med_complexity AS (
  -- For each admission, count unique drugs and unique serotonergic drugs in first 48h
  SELECT
    s.subject_id,
    s.hadm_id,
    s.group_type,
    COUNT(DISTINCT m.drug_name) AS num_unique_drugs_48h,
    COUNT(DISTINCT CASE WHEN sd.drug IS NOT NULL OR m.drug_name LIKE '%st. john%' THEN m.drug_name END) AS num_serotonergic_drugs_48h,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    s.age_at_admit
  FROM
    study_cohort s
    LEFT JOIN meds_48h m
      ON s.subject_id = m.subject_id AND s.hadm_id = m.hadm_id
    LEFT JOIN serotonergic_drugs sd
      ON m.drug_name LIKE CONCAT('%', sd.drug, '%')
  GROUP BY
    s.subject_id, s.hadm_id, s.group_type, s.admittime, s.dischtime, s.hospital_expire_flag, s.age_at_admit
),
quartiles AS (
  -- Compute top complexity quartile cutoff
  SELECT
    APPROX_QUANTILES(num_unique_drugs_48h, 4)[OFFSET(3)] AS top_quartile_cutoff
  FROM
    med_complexity
),
final AS (
  -- Add flags for serotonergic drug count and top quartile
  SELECT
    mc.*,
    CASE WHEN mc.num_serotonergic_drugs_48h >= 2 THEN '>=2' ELSE '<2' END AS serotonergic_group,
    CASE WHEN mc.num_unique_drugs_48h >= q.top_quartile_cutoff THEN 1 ELSE 0 END AS top_complexity_quartile,
    DATETIME_DIFF(mc.dischtime, mc.admittime, HOUR)/24.0 AS los_days
  FROM
    med_complexity mc
    CROSS JOIN quartiles q
)
-- 1. Medication complexity distribution (histogram) for cases vs controls
SELECT
  'complexity_distribution' AS analysis_type,
  group_type,
  num_unique_drugs_48h,
  COUNT(*) AS num_patients,
  NULL AS avg_los_days,
  NULL AS mortality_rate
FROM final
GROUP BY group_type, num_unique_drugs_48h

UNION ALL

-- 2. Outcomes for patients with >=2 vs <2 serotonergic drugs (LOS, mortality)
SELECT
  'serotonergic_outcomes' AS analysis_type,
  serotonergic_group AS group_type,
  NULL AS num_unique_drugs_48h,
  COUNT(*) AS num_patients,
  AVG(los_days) AS avg_los_days,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS mortality_rate
FROM final
GROUP BY serotonergic_group

UNION ALL

-- 3. Outcomes for top complexity quartile vs others (LOS, mortality)
SELECT
  'top_quartile_outcomes' AS analysis_type,
  CASE WHEN top_complexity_quartile = 1 THEN 'top_quartile' ELSE 'others' END AS group_type,
  NULL AS num_unique_drugs_48h,
  COUNT(*) AS num_patients,
  AVG(los_days) AS avg_los_days,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS mortality_rate
FROM final
GROUP BY top_complexity_quartile;
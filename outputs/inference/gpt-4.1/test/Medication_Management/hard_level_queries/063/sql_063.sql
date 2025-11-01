WITH pneumonia_admissions AS (
  -- Select male patients aged 48-58 with pneumonia diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      -- ICD-10 pneumonia: J12-J18
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486
      OR (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS INT64) BETWEEN 480 AND 486)
    )
),

first_admissions AS (
  -- Only first admission per patient
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM pneumonia_admissions
  GROUP BY subject_id
),

cohort AS (
  -- Cohort: male, 48-58, pneumonia, first admission
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.deathtime,
    pa.hospital_expire_flag,
    pa.anchor_age
  FROM pneumonia_admissions pa
    JOIN first_admissions fa
      ON pa.subject_id = fa.subject_id AND pa.admittime = fa.first_admittime
),

meds_24h AS (
  -- Medications administered in first 24h (from EMAR and Prescriptions)
  SELECT
    c.subject_id,
    c.hadm_id,
    LOWER(e.medication) AS med_name
  FROM cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
      AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  UNION DISTINCT
  SELECT
    c.subject_id,
    c.hadm_id,
    LOWER(p.drug) AS med_name
  FROM cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
      AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),

med_complexity AS (
  -- Count unique meds per patient in first 24h
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT med_name) AS med_count
  FROM meds_24h
  GROUP BY subject_id, hadm_id
),

serotonergic_meds AS (
  -- List of serotonergic drugs (expand as needed)
  SELECT 'sertraline' AS med UNION ALL
  SELECT 'fluoxetine' UNION ALL
  SELECT 'paroxetine' UNION ALL
  SELECT 'citalopram' UNION ALL
  SELECT 'escitalopram' UNION ALL
  SELECT 'venlafaxine' UNION ALL
  SELECT 'duloxetine' UNION ALL
  SELECT 'trazodone' UNION ALL
  SELECT 'tramadol' UNION ALL
  SELECT 'linezolid' UNION ALL
  SELECT 'sumatriptan' UNION ALL
  SELECT 'zolmitriptan' UNION ALL
  SELECT 'fentanyl' UNION ALL
  SELECT 'meperidine' UNION ALL
  SELECT 'methylene blue' UNION ALL
  SELECT 'bupropion' UNION ALL
  SELECT 'buspirone' UNION ALL
  SELECT 'mirtazapine' UNION ALL
  SELECT 'amitriptyline' UNION ALL
  SELECT 'nortriptyline' UNION ALL
  SELECT 'imipramine' UNION ALL
  SELECT 'clomipramine'
),

serotonergic_flag AS (
  -- Flag patients with serotonergic drug in first 24h
  SELECT
    mc.subject_id,
    mc.hadm_id,
    MAX(CASE WHEN sm.med IS NOT NULL THEN 1 ELSE 0 END) AS serotonergic_risk
  FROM med_complexity mc
    LEFT JOIN meds_24h m ON mc.subject_id = m.subject_id AND mc.hadm_id = m.hadm_id
    LEFT JOIN serotonergic_meds sm ON m.med_name LIKE CONCAT('%', sm.med, '%')
  GROUP BY mc.subject_id, mc.hadm_id
),

icu_admissions AS (
  -- Identify ICU admissions in cohort
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),

final_cohort AS (
  -- Combine all info
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.hospital_expire_flag,
    c.anchor_age,
    IFNULL(mc.med_count, 0) AS med_count,
    IFNULL(sf.serotonergic_risk, 0) AS serotonergic_risk,
    CASE WHEN ia.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days
  FROM cohort c
    LEFT JOIN med_complexity mc ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
    LEFT JOIN serotonergic_flag sf ON c.subject_id = sf.subject_id AND c.hadm_id = sf.hadm_id
    LEFT JOIN icu_admissions ia ON c.subject_id = ia.subject_id AND c.hadm_id = ia.hadm_id
),

-- Medication complexity stats
med_complexity_stats AS (
  SELECT
    COUNT(*) AS n_patients,
    AVG(med_count) AS mean_med_complexity,
    APPROX_QUANTILES(med_count, 4)[OFFSET(1)] AS p25_med_complexity,
    APPROX_QUANTILES(med_count, 4)[OFFSET(2)] AS p50_med_complexity,
    APPROX_QUANTILES(med_count, 4)[OFFSET(3)] AS p75_med_complexity
  FROM final_cohort
),

-- LOS and mortality for serotonergic risk vs ICU patients
los_mortality_base AS (
  SELECT
    CASE
      WHEN serotonergic_risk = 1 THEN 'Serotonergic Risk'
      WHEN icu_flag = 1 THEN 'ICU Patient'
      ELSE 'Other'
    END AS group_type,
    COUNT(*) AS n_patients,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS mortality_rate
  FROM final_cohort
  WHERE serotonergic_risk = 1 OR icu_flag = 1
  GROUP BY group_type
),

-- Compute top quartile LOS threshold per group
top_quartile_threshold AS (
  SELECT
    CASE
      WHEN serotonergic_risk = 1 THEN 'Serotonergic Risk'
      WHEN icu_flag = 1 THEN 'ICU Patient'
      ELSE 'Other'
    END AS group_type,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los
  FROM final_cohort
  WHERE serotonergic_risk = 1 OR icu_flag = 1
  GROUP BY group_type
),

-- Compute top quartile mortality per group
top_quartile_mortality AS (
  SELECT
    tqt.group_type,
    COUNT(*) AS n_top_quartile,
    SUM(CASE WHEN fc.hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS top_quartile_mortality_rate
  FROM final_cohort fc
    JOIN top_quartile_threshold tqt
      ON
        ((fc.serotonergic_risk = 1 AND tqt.group_type = 'Serotonergic Risk')
         OR (fc.icu_flag = 1 AND tqt.group_type = 'ICU Patient'))
  WHERE fc.los_days >= tqt.p75_los
    AND (fc.serotonergic_risk = 1 OR fc.icu_flag = 1)
  GROUP BY tqt.group_type
)

-- Final output
SELECT
  'Medication Complexity Distribution' AS section,
  n_patients,
  mean_med_complexity,
  p25_med_complexity,
  p50_med_complexity,
  p75_med_complexity,
  NULL AS group_type,
  NULL AS mean_los,
  NULL AS p75_los,
  NULL AS mortality_rate,
  NULL AS n_top_quartile,
  NULL AS top_quartile_mortality_rate
FROM med_complexity_stats

UNION ALL

SELECT
  'LOS and Mortality Comparison' AS section,
  NULL AS n_patients,
  NULL AS mean_med_complexity,
  NULL AS p25_med_complexity,
  NULL AS p50_med_complexity,
  NULL AS p75_med_complexity,
  lmb.group_type,
  lmb.mean_los,
  lmb.p75_los,
  lmb.mortality_rate,
  tqm.n_top_quartile,
  tqm.top_quartile_mortality_rate
FROM los_mortality_base lmb
LEFT JOIN top_quartile_mortality tqm
  ON lmb.group_type = tqm.group_type
;
WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(did.long_title) LIKE '%pneumonia%'
),

meds_first24 AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    p.drug,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%sertraline%'
        OR LOWER(p.drug) LIKE '%fluoxetine%'
        OR LOWER(p.drug) LIKE '%citalopram%'
        OR LOWER(p.drug) LIKE '%escitalopram%'
        OR LOWER(p.drug) LIKE '%paroxetine%'
        OR LOWER(p.drug) LIKE '%venlafaxine%'
        OR LOWER(p.drug) LIKE '%duloxetine%'
        OR LOWER(p.drug) LIKE '%phenelzine%'
        OR LOWER(p.drug) LIKE '%tranylcypromine%'
        OR LOWER(p.drug) LIKE '%sumatriptan%'
        OR LOWER(p.drug) LIKE '%rizatriptan%'
        OR LOWER(p.drug) LIKE '%tramadol%'
        OR LOWER(p.drug) LIKE '%dextromethorphan%'
        OR LOWER(p.drug) LIKE '%linezolid%'
        OR LOWER(p.drug) LIKE '%methylene blue%'
        OR LOWER(p.drug) LIKE '%clomipramine%'
        OR LOWER(p.drug) LIKE '%amitriptyline%'
        OR LOWER(p.drug) LIKE '%nortriptyline%'
        OR LOWER(p.drug) LIKE '%protriptyline%'
        OR LOWER(p.drug) LIKE '%maprotiline%'
        OR LOWER(p.drug) LIKE '%bupropion%'
        OR LOWER(p.drug) LIKE '%trazodone%'
        OR LOWER(p.drug) LIKE '%mirtazapine%'
        OR LOWER(p.drug) LIKE '%pethidine%'
        OR LOWER(p.drug) LIKE '%fentanyl%'
        OR LOWER(p.drug) LIKE '%meperidine%'
      THEN 1
      ELSE 0
    END AS has_serotonergic_drug
  FROM cohort c
  INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL '24 hours'
    AND p.drug IS NOT NULL
    AND TRIM(p.drug) != ''
),

patient_med_complexity AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT drug) AS num_distinct_meds
  FROM meds_first24
  GROUP BY subject_id
),

los_mortality AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    EXTRACT(EPOCH FROM (c.dischtime - c.admittime)) / 3600 / 24 AS los_days,
    c.hospital_expire_flag
  FROM cohort c
),

sero_group AS (
  SELECT 
    l.subject_id,
    l.los_days,
    l.hospital_expire_flag,
    COALESCE(MAX(m.has_serotonergic_drug), 0) AS has_serotonergic_drug
  FROM los_mortality l
  LEFT JOIN meds_first24 m ON l.subject_id = m.subject_id
  GROUP BY l.subject_id, l.los_days, l.hospital_expire_flag
),

complexity_stats AS (
  SELECT 
    AVG(num_distinct_meds) AS mean_med_complexity,
    PERCENTILE_CONT(num_distinct_meds, 0.25) AS p25_med_complexity,
    PERCENTILE_CONT(num_distinct_meds, 0.50) AS p50_med_complexity,
    PERCENTILE_CONT(num_distinct_meds, 0.75) AS p75_med_complexity
  FROM patient_med_complexity
),

grouped_outcomes AS (
  SELECT 
    has_serotonergic_drug,
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM sero_group
  GROUP BY has_serotonergic_drug
),

top_quartile_los AS (
  SELECT 
    PERCENTILE_CONT(los_days, 0.75) AS p75_los,
    AVG(CASE WHEN los_days >= PERCENTILE_CONT(los_days, 0.75) THEN hospital_expire_flag ELSE NULL END) AS mortality_in_top_quartile
  FROM los_mortality
)

SELECT 
  c.mean_med_complexity,
  c.p25_med_complexity,
  c.p50_med_complexity,
  c.p75_med_complexity,
  g.has_serotonergic_drug,
  g.mean_los,
  g.mortality_rate,
  t.p75_los,
  t.mortality_in_top_quartile
FROM complexity_stats c
CROSS JOIN grouped_outcomes g
CROSS JOIN top_quartile_los t;
WITH base_admissions AS (
  -- Female inpatients aged 48-58 at admission
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
),
cases_controls AS (
  -- Flag cases (hemorrhagic stroke) vs controls (no stroke)
  SELECT 
    ba.*,
    CASE 
      WHEN d.hadm_id IS NOT NULL THEN 'case'
      ELSE 'control'
    END AS group_type
  FROM base_admissions ba
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE (di.icd_version = 9 AND di.icd_code IN ('430', '431', '432'))
       OR (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
  ) d ON ba.hadm_id = d.hadm_id
),
med_complexity AS (
  -- First 48h medication complexity and serotonergic count
  SELECT 
    cc.hadm_id,
    cc.group_type,
    COUNT(DISTINCT ph.medication) AS complexity,
    COUNT(DISTINCT CASE 
      WHEN LOWER(ph.medication) IN ('citalopram', 'escitalopram', 'fluoxetine', 'fluvoxamine', 
                                    'paroxetine', 'sertraline', 'venlafaxine', 'duloxetine', 
                                    'trazodone', 'sumatriptan') 
        OR LOWER(ph.medication) LIKE '%ssri%' 
        OR LOWER(ph.medication) LIKE '%snri%'
      THEN ph.medication 
    END) AS sero_count
  FROM cases_controls cc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON cc.hadm_id = ph.hadm_id
  WHERE ph.starttime >= cc.admittime 
    AND ph.starttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 2 DAY)
    AND ph.medication IS NOT NULL
    AND TRIM(ph.medication) != ''
  GROUP BY cc.hadm_id, cc.group_type
),
all_patients AS (
  -- All patients with med data (left join to include zero-complexity if any)
  SELECT 
    cc.hadm_id,
    cc.group_type,
    cc.los_days,
    cc.hospital_expire_flag,
    COALESCE(mc.complexity, 0) AS complexity,
    COALESCE(mc.sero_count, 0) AS sero_count
  FROM cases_controls cc
  LEFT JOIN med_complexity mc ON cc.hadm_id = mc.hadm_id
),
quartiles AS (
  -- Overall complexity quartiles
  SELECT 
    APPROX_QUANTILES(complexity, 4)[OFFSET(3)] AS q4_threshold
  FROM all_patients
),
top_quartile AS (
  -- Patients in top complexity quartile
  SELECT 
    ap.*,
    CASE WHEN ap.complexity >= q.q4_threshold THEN 1 ELSE 0 END AS in_top_quartile,
    CASE WHEN ap.sero_count >= 2 THEN '>=2' ELSE '<2' END AS sero_bucket
  FROM all_patients ap
  CROSS JOIN quartiles q
)
-- Section 1: Medication complexity distribution (counts by group and complexity)
SELECT 'Distribution' AS section, group_type, CAST(complexity AS STRING) AS metric, CAST(COUNT(*) AS STRING) AS value
FROM top_quartile
GROUP BY group_type, complexity

UNION ALL

-- Section 2a: Serotonergic LOS (>=2 vs <2, full cohort)
SELECT 'Serotonergic Outcomes' AS section, 
       group_type, 
       sero_bucket || ' - LOS' AS metric, 
       CAST(AVG(los_days) AS STRING) AS value
FROM top_quartile
GROUP BY group_type, sero_bucket

UNION ALL

-- Section 2b: Serotonergic Mortality (>=2 vs <2, full cohort)
SELECT 'Serotonergic Outcomes' AS section, 
       group_type, 
       sero_bucket || ' - Mortality' AS metric, 
       CAST(SUM(hospital_expire_flag) * 1.0 / COUNT(*) AS STRING) AS value
FROM top_quartile
GROUP BY group_type, sero_bucket

UNION ALL

-- Section 3a: Top Quartile LOS (by group)
SELECT 'Top Quartile Outcomes' AS section, 
       group_type, 
       'LOS' AS metric, 
       CAST(AVG(los_days) AS STRING) AS value
FROM top_quartile
WHERE in_top_quartile = 1
GROUP BY group_type

UNION ALL

-- Section 3b: Top Quartile Mortality (by group)
SELECT 'Top Quartile Outcomes' AS section, 
       group_type, 
       'Mortality' AS metric, 
       CAST(SUM(hospital_expire_flag) * 1.0 / COUNT(*) AS STRING) AS value
FROM top_quartile
WHERE in_top_quartile = 1
GROUP BY group_type

ORDER BY section, group_type, metric;
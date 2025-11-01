WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND d.drg_code IN ('956', '957', '958')
), 
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE admission_age BETWEEN 68 AND 78
),
medications AS (
  SELECT 
    c.hadm_id,
    e.medication,
    e.charttime
  FROM filtered_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
cohort_data AS (
  SELECT 
    c.hadm_id,
    c.admission_age,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT m.medication) AS complexity,
    COUNT(DISTINCT CASE 
      WHEN LOWER(m.medication) LIKE '%citalopram%' OR LOWER(m.medication) LIKE '%escitalopram%' 
        OR LOWER(m.medication) LIKE '%fluoxetine%' OR LOWER(m.medication) LIKE '%fluvoxamine%' 
        OR LOWER(m.medication) LIKE '%paroxetine%' OR LOWER(m.medication) LIKE '%sertraline%' 
        OR LOWER(m.medication) LIKE '%desvenlafaxine%' OR LOWER(m.medication) LIKE '%duloxetine%' 
        OR LOWER(m.medication) LIKE '%venlafaxine%' OR LOWER(m.medication) LIKE '%amitriptyline%' 
        OR LOWER(m.medication) LIKE '%clomipramine%' OR LOWER(m.medication) LIKE '%imipramine%' 
        OR LOWER(m.medication) LIKE '%nortriptyline%' OR LOWER(m.medication) LIKE '%phenelzine%' 
        OR LOWER(m.medication) LIKE '%selegiline%' OR LOWER(m.medication) LIKE '%tranylcypromine%' 
        OR LOWER(m.medication) LIKE '%bupropion%' OR LOWER(m.medication) LIKE '%mirtazapine%' 
        OR LOWER(m.medication) LIKE '%trazodone%' OR LOWER(m.medication) LIKE '%tramadol%' 
        OR LOWER(m.medication) LIKE '%meperidine%' OR LOWER(m.medication) LIKE '%methadone%' 
        OR LOWER(m.medication) LIKE '%tapentadol%' OR LOWER(m.medication) LIKE '%sumatriptan%' 
        OR LOWER(m.medication) LIKE '%rizatriptan%' OR LOWER(m.medication) LIKE '%ondansetron%' 
        OR LOWER(m.medication) LIKE '%granisetron%' OR LOWER(m.medication) LIKE '%linezolid%' 
        OR LOWER(m.medication) LIKE '%dextromethorphan%' OR LOWER(m.medication) LIKE '%lithium%' 
      THEN m.medication 
    END) AS serotonergic_count
  FROM filtered_cohort c
  LEFT JOIN medications m
    ON c.hadm_id = m.hadm_id
  GROUP BY 
    c.hadm_id, c.admission_age, c.admittime, c.dischtime, c.hospital_expire_flag
),
final_cohort AS (
  SELECT 
    *,
    CASE WHEN serotonergic_count >= 2 THEN 1 ELSE 0 END AS serotonergic_risk,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM cohort_data
),
serotonergic_groups AS (
  SELECT 
    serotonergic_risk,
    COUNT(*) AS n,
    APPROX_QUANTILES(complexity, 4) AS quartiles_arr,
    AVG(complexity) AS avg_complexity,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM final_cohort
  GROUP BY serotonergic_risk
),
serotonergic_results AS (
  SELECT 
    'serotonergic_risk' AS analysis_type,
    serotonergic_risk AS group_flag,
    n,
    quartiles_arr[OFFSET(1)] AS q1,
    quartiles_arr[OFFSET(2)] AS median,
    quartiles_arr[OFFSET(3)] AS q3,
    avg_complexity,
    avg_los,
    mortality_rate
  FROM serotonergic_groups
),
percentile AS (
  SELECT 
    APPROX_QUANTILES(complexity, 4) AS quartiles_arr
  FROM final_cohort
),
top_quartile_data AS (
  SELECT 
    *,
    CASE 
      WHEN complexity >= (SELECT quartiles_arr[OFFSET(3)] FROM percentile) THEN 1 
      ELSE 0 
    END AS top_quartile
  FROM final_cohort
),
top_quartile_groups AS (
  SELECT 
    top_quartile AS group_flag,
    COUNT(*) AS n,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM top_quartile_data
  GROUP BY top_quartile
),
top_quartile_results AS (
  SELECT 
    'top_quartile' AS analysis_type,
    group_flag,
    n,
    NULL AS q1,
    NULL AS median,
    NULL AS q3,
    NULL AS avg_complexity,
    avg_los,
    mortality_rate
  FROM top_quartile_groups
)
SELECT * FROM serotonergic_results
UNION ALL
SELECT * FROM top_quartile_results
ORDER BY analysis_type, group_flag;
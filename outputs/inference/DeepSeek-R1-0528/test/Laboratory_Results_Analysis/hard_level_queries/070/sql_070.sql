WITH hemorrhagic_stroke AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430', '431', '432')) OR
    (icd_version = 10 AND icd_code IN ('I60', 'I61', 'I62'))
),
base_cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    CASE WHEN h.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_case
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN hemorrhagic_stroke h
    ON a.hadm_id = h.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),
cohort_labs AS (
  SELECT 
    c.hadm_id,
    le.itemid,
    dli.label AS lab_name,
    c.is_case
  FROM base_cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    le.flag IS NOT NULL 
    AND le.flag <> 'normal'
),
case_instability AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT itemid) AS instability_score
  FROM cohort_labs
  WHERE is_case = 1
  GROUP BY hadm_id
),
case_with_quartile AS (
  SELECT 
    c.*,
    COALESCE(ci.instability_score, 0) AS instability_score,
    NTILE(4) OVER (ORDER BY COALESCE(ci.instability_score, 0)) AS quartile
  FROM base_cohort c
  LEFT JOIN case_instability ci
    ON c.hadm_id = ci.hadm_id
  WHERE c.is_case = 1
),
cohort_groups AS (
  SELECT 
    hadm_id,
    quartile AS group_id,
    CONCAT('Quartile ', CAST(quartile AS STRING)) AS group_label
  FROM case_with_quartile
  UNION ALL
  SELECT 
    hadm_id,
    5 AS group_id,
    'Control' AS group_label
  FROM base_cohort
  WHERE is_case = 0
),
group_summary AS (
  SELECT 
    g.group_id,
    g.group_label,
    AVG(DATETIME_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los,
    AVG(c.hospital_expire_flag) * 100 AS mortality_rate
  FROM cohort_groups g
  INNER JOIN base_cohort c
    ON g.hadm_id = c.hadm_id
  GROUP BY g.group_id, g.group_label
),
group_counts AS (
  SELECT 
    group_id, 
    COUNT(DISTINCT hadm_id) AS total_patients
  FROM cohort_groups
  GROUP BY group_id
),
lab_rates AS (
  SELECT 
    g.group_id,
    g.group_label,
    cl.lab_name,
    COUNT(DISTINCT g.hadm_id) AS abnormal_count,
    (COUNT(DISTINCT g.hadm_id) * 100.0) / gc.total_patients AS abnormal_rate
  FROM cohort_groups g
  INNER JOIN cohort_labs cl
    ON g.hadm_id = cl.hadm_id
  INNER JOIN group_counts gc
    ON g.group_id = gc.group_id
  GROUP BY g.group_id, g.group_label, cl.lab_name, gc.total_patients
),
combined AS (
  SELECT 
    group_id,
    group_label,
    NULL AS lab_name,
    avg_los,
    mortality_rate,
    NULL AS abnormal_rate
  FROM group_summary
  UNION ALL
  SELECT 
    group_id,
    group_label,
    lab_name,
    NULL AS avg_los,
    NULL AS mortality_rate,
    abnormal_rate
  FROM lab_rates
)
SELECT *
FROM combined
ORDER BY group_id, lab_name;
WITH cohort AS (
  -- Female patients aged 71-81
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.icd_version = '10'  -- ICD-10 for modern codes
    AND d.icd_code LIKE 'T8%'  -- T80-T88: Complications of care
    AND d.seq_num = 1  -- Primary diagnosis
),
icu_flag AS (
  -- Add ICU flag
  SELECT c.*, 
         CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS stratum
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),
los_quartiles AS (
  -- Add LOS and quartile (use hours for precision)
  SELECT *, 
         TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
         PERCENT_RANK() OVER (PARTITION BY stratum ORDER BY TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS pr
  FROM icu_flag
),
quartiled AS (
  -- Assign quartiles
  SELECT *,
         CASE 
           WHEN pr <= 0.25 THEN 'Q1'
           WHEN pr <= 0.50 THEN 'Q2'
           WHEN pr <= 0.75 THEN 'Q3'
           ELSE 'Q4'
         END AS quartile
  FROM los_quartiles
),
mortality_base AS (
  -- Base for mortality aggregations
  SELECT 
    stratum,
    quartile,
    COUNT(*) AS n_total,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths
  FROM quartiled
  GROUP BY stratum, quartile
),
mortality_metrics AS (
  -- Compute % mortality, abs/rel vs Q1 per stratum
  SELECT 
    stratum,
    quartile,
    n_total,
    n_deaths,
    SAFE_DIVIDE(n_deaths, n_total) * 100 AS mortality_pct,
    CASE 
      WHEN quartile = 'Q1' THEN 0
      ELSE mortality_pct - FIRST_VALUE(mortality_pct) OVER (PARTITION BY stratum)
    END AS abs_diff_vs_q1,
    CASE 
      WHEN quartile = 'Q1' THEN 1.0
      ELSE SAFE_DIVIDE(
        SAFE_DIVIDE(n_deaths, n_total),
        FIRST_VALUE(SAFE_DIVIDE(n_deaths, n_total)) OVER (PARTITION BY stratum)
      )
    END AS rel_risk_vs_q1
  FROM mortality_base
),
ventilation AS (
  -- % mechanical ventilation (ICU only)
  SELECT 
    stratum,
    COUNT(DISTINCT CASE WHEN stratum = 'ICU' AND vent.hadm_id IS NOT NULL THEN vent.hadm_id END) * 100.0 / 
    COUNT(DISTINCT CASE WHEN stratum = 'ICU' THEN hadm_id END) AS vent_pct
  FROM quartiled q
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid IN (225468, 225821, 227041)  -- Ventilation status/settings
  ) vent ON q.subject_id = vent.subject_id AND q.hadm_id = vent.hadm_id
  GROUP BY stratum
),
vasopressors AS (
  -- % vasopressors (ICU only)
  SELECT 
    stratum,
    COUNT(DISTINCT CASE WHEN stratum = 'ICU' AND vaso.hadm_id IS NOT NULL THEN vaso.hadm_id END) * 100.0 / 
    COUNT(DISTINCT CASE WHEN stratum = 'ICU' THEN hadm_id END) AS vaso_pct
  FROM quartiled q
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (225798, 225151, 220615, 225160, 225163)  -- Norepi, epi, phenylephrine, etc.
      AND amount > 0
      AND statusdescription != 'Rewritten'
      AND endtime IS NOT NULL
  ) vaso ON q.subject_id = vaso.subject_id AND q.hadm_id = vaso.hadm_id
  GROUP BY stratum
),
rrt AS (
  -- % RRT (ICU only)
  SELECT 
    stratum,
    COUNT(DISTINCT CASE WHEN stratum = 'ICU' AND rrt.hadm_id IS NOT NULL THEN rrt.hadm_id END) * 100.0 / 
    COUNT(DISTINCT CASE WHEN stratum = 'ICU' THEN hadm_id END) AS rrt_pct
  FROM quartiled q
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (225826, 225170, 228537)  -- CVVH, etc.
      AND amount > 0
      AND statusdescription != 'Rewritten'
      AND endtime IS NOT NULL
    UNION DISTINCT
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (225826, 225170, 228537, 225468, 225479)  -- Hemodialysis/CVVH procedures
  ) rrt ON q.subject_id = rrt.subject_id AND q.hadm_id = rrt.hadm_id
  GROUP BY stratum
)
-- Final output: Join metrics (interventions constant per stratum)
SELECT 
  m.stratum,
  m.quartile,
  m.n_total,
  ROUND(m.mortality_pct, 2) AS mortality_pct,
  ROUND(COALESCE(m.abs_diff_vs_q1, 0), 2) AS abs_diff_vs_q1,
  ROUND(COALESCE(m.rel_risk_vs_q1, 1.0), 2) AS rel_risk_vs_q1,
  ROUND(COALESCE(v.vent_pct, 0.0), 2) AS vent_pct,
  ROUND(COALESCE(va.vaso_pct, 0.0), 2) AS vaso_pct,
  ROUND(COALESCE(r.rrt_pct, 0.0), 2) AS rrt_pct
FROM mortality_metrics m
LEFT JOIN ventilation v ON m.stratum = v.stratum
LEFT JOIN vasopressors va ON m.stratum = va.stratum
LEFT JOIN rrt r ON m.stratum = r.stratum
ORDER BY m.stratum, 
  CASE m.quartile WHEN 'Q1' THEN 1 WHEN 'Q2' THEN 2 WHEN 'Q3' THEN 3 WHEN 'Q4' THEN 4 END;
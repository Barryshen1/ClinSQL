WITH base_population AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 41 AND 51
),
with_icu AS (
  SELECT 
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag
  FROM base_population b
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON b.hadm_id = i.hadm_id
),
with_neutropenia AS (
  SELECT 
    w.hadm_id
  FROM with_icu w
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON w.hadm_id = l.hadm_id
  WHERE l.itemid = 51146  -- Absolute neutrophil count
    AND l.valuenum < 1500
    AND l.valuenum IS NOT NULL
  GROUP BY w.hadm_id
),
with_fever AS (
  SELECT DISTINCT
    w.hadm_id
  FROM with_icu w
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON w.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE c.itemid = 223762  -- Temperature Celsius
    AND c.valuenum > 38.0
    AND c.valuenum IS NOT NULL
),
cohort AS (
  SELECT 
    w.*
  FROM with_icu w
  INNER JOIN with_neutropenia n ON w.hadm_id = n.hadm_id
  INNER JOIN with_fever f ON w.hadm_id = f.hadm_id
),
medication_count AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT drug) AS med_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.admittime
    AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),
tertile_cohort AS (
  SELECT 
    c.*,
    m.med_count,
    NTILE(3) OVER (ORDER BY m.med_count) AS tertile
  FROM cohort c
  INNER JOIN medication_count m
    ON c.hadm_id = m.hadm_id
),
readmission_flag AS (
  SELECT 
    t.*,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` r 
      WHERE r.subject_id = t.subject_id 
        AND r.admittime > t.dischtime 
        AND r.admittime <= DATETIME_ADD(t.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmission_30d
  FROM tertile_cohort t
)
SELECT
  tertile,
  APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0, 100)[OFFSET(50)] AS median_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmission_30d) * 100 AS readmission_30d_pct
FROM readmission_flag
GROUP BY tertile
ORDER BY tertile;
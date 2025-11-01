WITH female_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),
stroke_flags AS (
  SELECT
    hadm_id,
    MAX(CASE
      WHEN (icd_version = 9 AND icd_code IN ('430','431'))
        OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%'))
      THEN 1 ELSE 0 END) AS is_hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
meds_48h AS (
  SELECT
    e.hadm_id,
    LOWER(e.medication) AS medname
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN female_inpatients f
    ON e.hadm_id = f.hadm_id
  WHERE e.charttime BETWEEN f.admittime AND TIMESTAMP_ADD(f.admittime, INTERVAL 48 HOUR)
),
complexity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT medname) AS complexity_score,
    COUNT(DISTINCT CASE WHEN medname LIKE '%sertraline%'
          OR medname LIKE '%fluoxetine%'
          OR medname LIKE '%citalopram%'
          OR medname LIKE '%paroxetine%'
          OR medname LIKE '%venlafaxine%'
          OR medname LIKE '%duloxetine%'
          OR medname LIKE '%buspirone%'
          OR medname LIKE '%trazodone%'
          OR medname LIKE '%linezolid%'
          OR medname LIKE '%sumatriptan%'
        THEN medname END) AS serotonergic_count
  FROM meds_48h
  GROUP BY hadm_id
),
combined AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    s.is_hemorrhagic_stroke,
    c.complexity_score,
    c.serotonergic_count,
    f.los_days,
    f.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY c.complexity_score DESC) AS complexity_quartile
  FROM female_inpatients f
  LEFT JOIN stroke_flags s
    ON f.hadm_id = s.hadm_id
  LEFT JOIN complexity c
    ON f.hadm_id = c.hadm_id
)
SELECT
  CASE WHEN is_hemorrhagic_stroke = 1 THEN 'Hemorrhagic Stroke' ELSE 'Control' END AS cohort,
  CASE WHEN serotonergic_count >= 2 THEN '>=2 serotonergic' ELSE '<2 serotonergic' END AS serotonergic_group,
  COUNT(*) AS admissions,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM combined
GROUP BY cohort, serotonergic_group
UNION ALL
SELECT
  'All' AS cohort,
  CASE WHEN complexity_quartile = 1 THEN 'Top quartile complexity' ELSE 'Other quartiles' END AS serotonergic_group,
  COUNT(*) AS admissions,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM combined
GROUP BY serotonergic_group;
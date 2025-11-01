WITH acs_adm AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (
      dd.long_title LIKE '%myocardial infarction%' OR
      dd.long_title LIKE '%unstable angina%' OR
      dd.long_title LIKE '%acute coronary%'
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 46 AND 56
),
troponin_hosp AS (
  SELECT le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli ON le.itemid = dli.itemid
  JOIN acs_adm aa ON le.hadm_id = aa.hadm_id
  WHERE (LOWER(dli.label) LIKE '%troponin%' AND LOWER(dli.label) LIKE '%troponin t%')
     AND le.charttime BETWEEN aa.admittime AND aa.dischtime
  UNION ALL
  SELECT ce.hadm_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON ce.itemid = di.itemid
  JOIN acs_adm aa ON ce.hadm_id = aa.hadm_id
  WHERE (LOWER(di.label) LIKE '%troponin%' AND LOWER(di.label) LIKE '%troponin t%')
     AND ce.charttime BETWEEN aa.admittime AND aa.dischtime
),
first_troponin AS (
  SELECT hadm_id, charttime, valuenum,
         ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM troponin_hosp
  WHERE valuenum IS NOT NULL
),
first_per_adm AS (
  SELECT hadm_id, valuenum
  FROM first_troponin
  WHERE rn = 1
),
category AS (
  SELECT hadm_id,
         CASE
           WHEN valuenum <= 14 THEN 'Normal'
           WHEN valuenum > 14 AND valuenum <= 52 THEN 'Borderline'
           WHEN valuenum > 52 THEN 'Myocardial Injury'
           ELSE NULL
         END AS tnt_category
  FROM first_per_adm
  WHERE valuenum IS NOT NULL
),
los AS (
  SELECT a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM acs_adm AS a
),
tot AS (
  SELECT COUNT(*) AS total_adm FROM category
)
SELECT
  c.tnt_category AS tnt_category,
  COUNT(*) AS admissions_within_category,
  ROUND(100.0 * COUNT(*) / t.total_adm, 2) AS pct_of_acs_admissions,
  AVG(l.los_days) AS mean_los_days
FROM category AS c
JOIN los AS l ON c.hadm_id = l.hadm_id
CROSS JOIN tot AS t
GROUP BY c.tnt_category, t.total_adm
ORDER BY c.tnt_category;
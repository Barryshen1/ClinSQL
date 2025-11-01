WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    a.admittime,
    i.intime,
    i.outtime,
    i.stay_id,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
      WHERE d_icd.subject_id = a.subject_id
        AND d_icd.hadm_id = a.hadm_id
        AND d.long_title LIKE '%septic shock%'
    )
),

map_low AS (
  SELECT
    c.subject_id,
    c.stay_id,
    COUNT(ce.itemid) AS map_low_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.stay_id = ce.stay_id
    AND ce.itemid = 52
    AND ce.charttime BETWEEN c.intime AND c.intime + INTERVAL 48 HOUR
    AND ce.valuenum < 65
  GROUP BY c.subject_id, c.stay_id
),

p95 AS (
  SELECT
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY map_low_count) AS p95_val
  FROM map_low
),

p90 AS (
  SELECT
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY map_low_count) AS p90_val
  FROM map_low
),

top_decile AS (
  SELECT
    m.subject_id,
    m.stay_id,
    m.map_low_count,
    CASE WHEN m.map_low_count >= p90.p90_val THEN 1 ELSE 0 END AS is_top_decile
  FROM map_low m
  CROSS JOIN p90
),

map_hr AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    AVG(CASE WHEN ce.itemid = 52 THEN ce.valuenum END) AS avg_map,
    SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN cohort c
    ON ce.subject_id = c.subject_id AND ce.stay_id = c.stay_id
  WHERE ce.charttime BETWEEN c.intime AND c.intime + INTERVAL 48 HOUR
  GROUP BY ce.subject_id, ce.stay_id
)

SELECT
  '95th_percentile' AS metric,
  p95.p95_val AS value,
  NULL AS avg_map,
  NULL AS avg_hr_count,
  NULL AS avg_los,
  NULL AS mortality
FROM p95

UNION ALL

SELECT
  'top_decile' AS metric,
  NULL AS value,
  AVG(mh.avg_map) AS avg_map,
  AVG(mh.hr_count) AS avg_hr_count,
  AVG(c.los) AS avg_los,
  AVG(c.hospital_expire_flag) AS mortality
FROM cohort c
JOIN top_decile td
  ON c.subject_id = td.subject_id AND c.stay_id = td.stay_id
JOIN map_hr mh
  ON c.subject_id = mh.subject_id AND c.stay_id = mh.stay_id
WHERE td.is_top_decile = 1

UNION ALL

SELECT
  'cohort' AS metric,
  NULL AS value,
  AVG(mh.avg_map) AS avg_map,
  AVG(mh.hr_count) AS avg_hr_count,
  AVG(c.los) AS avg_los,
  AVG(c.hospital_expire_flag) AS mortality
FROM cohort c
JOIN top_decile td
  ON c.subject_id = td.subject_id AND c.stay_id = td.stay_id
JOIN map_hr mh
  ON c.subject_id = mh.subject_id AND c.stay_id = mh.stay_id
WHERE td.is_top_decile = 0;
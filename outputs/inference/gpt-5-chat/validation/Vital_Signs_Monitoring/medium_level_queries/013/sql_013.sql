WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),
spo2_first48 AS (
  SELECT
    c.stay_id,
    AVG(e.valuenum) AS avg_spo2
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` e
    ON c.stay_id = e.stay_id
  JOIN spo2_items di
    ON e.itemid = di.itemid
  WHERE e.valuenum IS NOT NULL
    AND e.valueuom = '%'
    AND e.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
aki_flags AS (
  SELECT
    DISTINCT hadm_id,
    1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '584%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
),
stay_with_flags AS (
  SELECT
    s.stay_id,
    s.avg_spo2,
    c.hadm_id,
    CASE
      WHEN s.avg_spo2 < 90 THEN '<90'
      WHEN s.avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN s.avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      WHEN s.avg_spo2 > 95 THEN '>95'
    END AS spo2_category,
    IF(af.aki_flag IS NULL, 0, 1) AS aki_flag
  FROM spo2_first48 s
  JOIN cohort c
    ON s.stay_id = c.stay_id
  LEFT JOIN aki_flags af
    ON c.hadm_id = af.hadm_id
)
SELECT
  spo2_category,
  COUNT(*) AS stay_count,
  ROUND(100 * SUM(aki_flag) / COUNT(*), 1) AS aki_rate_percent
FROM stay_with_flags
GROUP BY spo2_category
ORDER BY spo2_category;
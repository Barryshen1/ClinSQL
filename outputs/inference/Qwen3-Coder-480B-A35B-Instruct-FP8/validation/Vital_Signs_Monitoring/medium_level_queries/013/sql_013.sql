WITH cohort AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),

spo2_first48 AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    di.label = 'SpO2'
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
),

aki_flag AS (
  SELECT DISTINCT
    hadm_id,
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN ('5849', 'N179') -- ICD-9 and ICD-10 for AKI
    AND icd_version IN (9, 10)
),

spo2_category AS (
  SELECT
    s.stay_id,
    s.avg_spo2,
    CASE
      WHEN s.avg_spo2 < 90 THEN '<90'
      WHEN s.avg_spo2 >= 90 AND s.avg_spo2 <= 92 THEN '90–92'
      WHEN s.avg_spo2 > 92 AND s.avg_spo2 <= 95 THEN '93–95'
      WHEN s.avg_spo2 > 95 THEN '>95'
    END AS spo2_group,
    c.subject_id,
    CASE WHEN a.subject_id IS NOT NULL THEN 1 ELSE 0 END AS aki
  FROM
    spo2_first48 s
  JOIN
    cohort c
  ON
    s.stay_id = c.stay_id
  LEFT JOIN
    aki_flag a
  ON
    c.hadm_id = a.hadm_id
)

SELECT
  spo2_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN aki = 1 THEN subject_id END) AS aki_count,
  ROUND(
    COUNT(DISTINCT CASE WHEN aki = 1 THEN subject_id END) * 100.0 /
    COUNT(DISTINCT subject_id),
    2
  ) AS aki_rate_percent
FROM
  spo2_category
GROUP BY
  spo2_group
ORDER BY
  CASE spo2_group
    WHEN '<90' THEN 1
    WHEN '90–92' THEN 2
    WHEN '93–95' THEN 3
    WHEN '>95' THEN 4
  END;
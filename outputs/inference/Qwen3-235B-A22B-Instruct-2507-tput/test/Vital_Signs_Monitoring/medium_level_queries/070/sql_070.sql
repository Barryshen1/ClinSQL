WITH patient_icu AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 90 AND 100
),

spo2_first_24h AS (
  SELECT
    pi.stay_id,
    AVG(ce.valuenum) AS mean_spo2_24h
  FROM patient_icu pi
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON pi.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'SpO2'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= pi.intime
    AND ce.charttime < DATETIME_ADD(pi.intime, INTERVAL 24 HOUR)
  GROUP BY pi.stay_id
),

aki_diagnosis AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'N17%'
    AND di.icd_version = 10
),

spo2_with_aki AS (
  SELECT
    s.stay_id,
    s.mean_spo2_24h,
    CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki
  FROM spo2_first_24h s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON s.stay_id = i.stay_id
  LEFT JOIN aki_diagnosis a ON i.hadm_id = a.hadm_id
),

spo2_groups AS (
  SELECT
    stay_id,
    mean_spo2_24h,
    has_aki,
    CASE
      WHEN mean_spo2_24h < 90 THEN '<90'
      WHEN mean_spo2_24h BETWEEN 90 AND 92 THEN '90-92'
      WHEN mean_spo2_24h BETWEEN 93 AND 95 THEN '93-95'
      WHEN mean_spo2_24h > 95 THEN '>95'
      ELSE NULL
    END AS spo2_group
  FROM spo2_with_aki
  WHERE mean_spo2_24h IS NOT NULL
)

SELECT
  spo2_group,
  COUNT(*) AS N,
  ROUND(AVG(mean_spo2_24h), 2) AS mean_spo2,
  ROUND(APPROX_QUANTILES(mean_spo2_24h, 100)[OFFSET(50)], 2) AS median_spo2,
  CONCAT(
    ROUND(APPROX_QUANTILES(mean_spo2_24h, 100)[OFFSET(25)], 2), ' - ',
    ROUND(APPROX_QUANTILES(mean_spo2_24h, 100)[OFFSET(75)], 2)
  ) AS iqr_spo2,
  ROUND(AVG(has_aki), 3) AS aki_rate
FROM spo2_groups
WHERE spo2_group IS NOT NULL
GROUP BY spo2_group
ORDER BY
  CASE spo2_group
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
    ELSE 5
  END;
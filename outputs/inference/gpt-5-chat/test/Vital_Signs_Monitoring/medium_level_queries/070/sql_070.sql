WITH aki_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '584%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
),
spo2_per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(c.valuenum) AS avg_spo2,
    CASE
      WHEN AVG(c.valuenum) < 90 THEN '<90'
      WHEN AVG(c.valuenum) BETWEEN 90 AND 92 THEN '90-92'
      WHEN AVG(c.valuenum) BETWEEN 93 AND 95 THEN '93-95'
      WHEN AVG(c.valuenum) > 95 THEN '>95'
    END AS spo2_bin,
    CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_aki
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON icu.subject_id = c.subject_id
    AND icu.stay_id = c.stay_id
    AND c.itemid IN (646, 220277) -- SpO2 itemids
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  LEFT JOIN aki_hadm a
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id, a.hadm_id
)
SELECT
  spo2_bin,
  COUNT(*) AS n_stays,
  AVG(avg_spo2) AS mean_spo2,
  APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)] AS median_spo2,
  (APPROX_QUANTILES(avg_spo2, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_spo2, 4)[OFFSET(1)]) AS iqr_spo2,
  SAFE_DIVIDE(SUM(is_aki), COUNT(*)) AS aki_rate
FROM spo2_per_stay
GROUP BY spo2_bin
ORDER BY spo2_bin;
WITH target_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.hadm_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),

spO2_avg AS (
  SELECT
    tp.stay_id,
    tp.hadm_id,
    AVG(c.valuenum) AS avg_spo2
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON tp.stay_id = c.stay_id
    AND c.itemid = 220277
    AND c.charttime BETWEEN tp.intime AND tp.intime + INTERVAL '48' HOUR
  GROUP BY tp.stay_id, tp.hadm_id
),

aki_status AS (
  SELECT
    d.hadm_id,
    CASE WHEN COUNT(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'N17%' THEN 1 END) > 0 THEN 1 ELSE 0 END AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
)

SELECT
  CASE
    WHEN sa.avg_spo2 < 90 THEN '<90'
    WHEN sa.avg_spo2 >= 90 AND sa.avg_spo2 <= 92 THEN '90-92'
    WHEN sa.avg_spo2 >= 93 AND sa.avg_spo2 <= 95 THEN '93-95'
    ELSE '>95'
  END AS spo2_category,
  COUNT(*) AS patient_count,
  SUM(COALESCE(aki_status.has_aki, 0)) AS aki_count,
  ROUND(SUM(COALESCE(aki_status.has_aki, 0)) * 100.0 / COUNT(*), 2) AS aki_rate
FROM spO2_avg sa
LEFT JOIN aki_status
  ON sa.hadm_id = aki_status.hadm_id
WHERE sa.avg_spo2 IS NOT NULL
GROUP BY spo2_category
ORDER BY spo2_category;
WITH 
patients_icu AS (
  SELECT p.subject_id, p.anchor_age, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 90 AND 100
),

spo2_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%SpO2%' AND linksto = 'chartevents'
),

avg_spo2 AS (
  SELECT pi.stay_id, AVG(ce.valuenum) AS avg_spo2
  FROM patients_icu pi
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pi.stay_id = ce.stay_id
  JOIN spo2_itemid si ON ce.itemid = si.itemid
  WHERE ce.charttime BETWEEN pi.intime AND TIMESTAMP_ADD(pi.intime, INTERVAL 24 HOUR)
  GROUP BY pi.stay_id
),

spo2_category AS (
  SELECT stay_id,
         CASE
           WHEN avg_spo2 < 90 THEN '<90'
           WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
           WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
           ELSE '>95'
         END AS spo2_group
  FROM avg_spo2
),

aki_patients AS (
  WITH creatinine_itemid AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label LIKE '%Creatinine%' AND linksto = 'chartevents'
  ),
  creatinine_levels AS (
    SELECT pi.stay_id, ce.valuenum, ce.charttime, pi.intime,
           ROW_NUMBER() OVER (PARTITION BY pi.stay_id ORDER BY ce.charttime) AS rn
    FROM patients_icu pi
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pi.stay_id = ce.stay_id
    JOIN creatinine_itemid ci ON ce.itemid = ci.itemid
    WHERE ce.charttime BETWEEN pi.intime AND TIMESTAMP_ADD(pi.intime, INTERVAL 24 HOUR)
  ),
  baseline_creatinine AS (
    SELECT stay_id, valuenum AS baseline
    FROM creatinine_levels
    WHERE rn = 1
  ),
  max_creatinine AS (
    SELECT stay_id, MAX(valuenum) AS max_creatinine
    FROM creatinine_levels
    GROUP BY stay_id
  )
  SELECT bc.stay_id, 
         CASE WHEN mc.max_creatinine >= 1.5 * bc.baseline THEN 1 ELSE 0 END AS aki
  FROM baseline_creatinine bc
  JOIN max_creatinine mc ON bc.stay_id = mc.stay_id
)

SELECT 
  sc.spo2_group,
  COUNT(*) AS N,
  AVG(avg_spo2) AS mean_spo2,
  PERCENTILE_CONT(avg_spo2, 0.5) AS median_spo2,
  PERCENTILE_CONT(avg_spo2, 0.25) AS q1_spo2,
  PERCENTILE_CONT(avg_spo2, 0.75) AS q3_spo2,
  AVG(aki) AS aki_rate
FROM spo2_category sc
JOIN avg_spo2 ON sc.stay_id = avg_spo2.stay_id
LEFT JOIN aki_patients ON sc.stay_id = aki_patients.stay_id
GROUP BY sc.spo2_group
ORDER BY sc.spo2_group;
WITH stroke_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         CASE 
           WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
           ELSE 'Other'
         END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I6%'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7  -- Focus on 1-7 days only
),
ultrasound_counts AS (
  SELECT sa.hadm_id,
         sa.los_group,
         COUNT(DISTINCT ce.charttime) AS ultrasound_count
  FROM stroke_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON sa.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.subject_id = ce.subject_id
    AND i.hadm_id = ce.hadm_id
    AND i.stay_id = ce.stay_id
    AND ce.charttime BETWEEN i.intime AND i.outtime  -- Within ICU stay
  INNER JOIN ultrasound_itemids ui
    ON ce.itemid = ui.itemid
  WHERE sa.los_group != 'Other'
  GROUP BY sa.hadm_id, sa.los_group
)
SELECT 
  los_group,
  COUNT(*) AS num_admissions,
  ROUND(AVG(ultrasound_count), 2) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM ultrasound_counts
GROUP BY los_group
ORDER BY 
  CASE los_group 
    WHEN '1-4 days' THEN 1 
    WHEN '5-7 days' THEN 2 
  END;
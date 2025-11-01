WITH eligible_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 90 AND 100
    AND a.hadm_id IS NOT NULL
    AND d.seq_num = 1
    AND (
      (d.icd_version = 10 AND (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%'))
      OR
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
    )
),
index_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum AS index_valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE l.itemid = 50925
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
    AND l.charttime >= a.admittime
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY l.hadm_id
    ORDER BY l.charttime ASC, l.labevent_id ASC
  ) = 1
)
SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days
FROM (
  SELECT
    e.hadm_id,
    e.admittime,
    e.dischtime,
    CASE
      WHEN it.index_valuenum <= 0.01 THEN 'normal'
      WHEN it.index_valuenum <= 0.10 THEN 'borderline'
      WHEN it.index_valuenum > 0.10 THEN 'elevated'
      ELSE NULL
    END AS troponin_category
  FROM eligible_admissions e
  LEFT JOIN index_troponin it
    ON e.hadm_id = it.hadm_id
)
WHERE troponin_category IS NOT NULL
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END
;
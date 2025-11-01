WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      (d.icd_version = '9' AND (d.icd_code LIKE '410.%' OR d.icd_code = '411.1'))
      OR
      (d.icd_version = '10' AND (d.icd_code = 'I20.0' OR d.icd_code LIKE 'I21.%' OR d.icd_code LIKE 'I22.%'))
    )
),
first_tnt AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.labevent_id ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c 
    ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 20078
    AND le.valuenum IS NOT NULL
    AND le.charttime >= c.admittime
)
SELECT 
  CASE 
    WHEN ft.valuenum < 0.014 THEN 'Normal'
    WHEN ft.valuenum >= 0.014 AND ft.valuenum < 0.05 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  ROUND(AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0), 2) AS mean_los_days
FROM cohort c
INNER JOIN first_tnt ft 
  ON c.hadm_id = ft.hadm_id AND ft.rn = 1
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'Normal' THEN 1 
    WHEN 'Borderline' THEN 2 
    ELSE 3 
  END
;
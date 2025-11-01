WITH eligible AS (
  -- Female patients aged 43-53 at admission with suspected ACS (proxy via ACS/Chest Pain ICD codes)
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    -- Suspected ACS proxies: AMI, other ischemic conditions, and chest pain
    AND (
          LOWER(di.icd_code) LIKE '410%'
          OR LOWER(di.icd_code) LIKE '411%'
          OR LOWER(di.icd_code) LIKE '413%'
          OR LOWER(di.icd_code) LIKE '786%'
        )
),
initial_chart AS (
  -- Earliest Troponin T test per admission
  SELECT l.hadm_id,
         l.subject_id,
         MIN(l.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON l.itemid = di.itemid
  JOIN eligible AS e
    ON e.hadm_id = l.hadm_id AND e.subject_id = l.subject_id
  WHERE LOWER(di.label) LIKE '%troponin t%'
     OR LOWER(di.label) LIKE '%troponin_t%'
  GROUP BY l.hadm_id, l.subject_id
),
initial_values AS (
  -- Get the actual value corresponding to the initial charttime
  SELECT iv.hadm_id,
         iv.subject_id,
         l.valuenum
  FROM initial_chart AS iv
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = iv.hadm_id
   AND l.subject_id = iv.subject_id
   AND l.charttime = iv.first_charttime
   AND l.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN iv.valuenum <= 0.04 THEN 'Normal'
    WHEN iv.valuenum > 0.04 AND iv.valuenum < 0.39 THEN 'Borderline'
    WHEN iv.valuenum >= 0.39 THEN 'Elevated'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_group,
  AVG(TIMESTAMP_DIFF(e.dischtime, e.admittime, SECOND) / 86400.0) AS avg_los_days
FROM initial_values AS iv
JOIN eligible AS e
  ON e.hadm_id = iv.hadm_id AND e.subject_id = iv.subject_id
GROUP BY troponin_category
ORDER BY troponin_category;
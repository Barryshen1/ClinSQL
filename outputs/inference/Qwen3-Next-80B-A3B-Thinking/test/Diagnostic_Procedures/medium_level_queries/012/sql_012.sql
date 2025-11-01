WITH acs_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code IN (
          'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4',
          'I22.0', 'I22.1', 'I22.2', 'I22.3', 'I22.4', 'I22.5', 
          'I22.6', 'I22.7', 'I22.8', 'I22.9'
        )
    )
),
ultrasound_count AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
    ON p.itemid = d.itemid
  WHERE 
    d.label LIKE '%echo%' 
    OR d.label LIKE '%ultrasound%' 
    OR d.label LIKE '%echocardiogram%'
  GROUP BY p.hadm_id
)
SELECT 
  CASE 
    WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  COUNT(a.hadm_id) AS patient_count,
  AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds
FROM acs_admissions a
LEFT JOIN ultrasound_count u 
  ON a.hadm_id = u.hadm_id
GROUP BY los_group
HAVING los_group IS NOT NULL;
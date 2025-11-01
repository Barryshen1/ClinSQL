WITH cohort AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (LOWER(di.long_title) LIKE '%diabetes mellitus type 2%' OR d.icd_code LIKE 'E11%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (LOWER(di.long_title) LIKE '%heart failure%' OR d.icd_code LIKE 'I50%')
    )
),
insulin_first AS (
  SELECT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '24 hours'
    AND LOWER(p.drug) LIKE '%insulin%'
),
insulin_last AS (
  SELECT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.dischtime - INTERVAL '24 hours' AND c.dischtime
    AND LOWER(p.drug) LIKE '%insulin%'
),
oral_first AS (
  SELECT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '24 hours'
    AND LOWER(p.route) = 'oral'
),
oral_last AS (
  SELECT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.dischtime - INTERVAL '24 hours' AND c.dischtime
    AND LOWER(p.route) = 'oral'
)
SELECT
  ROUND(100.0 * COUNT(i.hadm_id) / COUNT(c.hadm_id), 2) AS insulin_first_pct,
  ROUND(100.0 * COUNT(il.hadm_id) / COUNT(c.hadm_id), 2) AS insulin_last_pct,
  ROUND(100.0 * (COUNT(il.hadm_id) - COUNT(i.hadm_id)) / COUNT(c.hadm_id), 2) AS insulin_net_change,
  ROUND(100.0 * COUNT(o.hadm_id) / COUNT(c.hadm_id), 2) AS oral_first_pct,
  ROUND(100.0 * COUNT(ol.hadm_id) / COUNT(c.hadm_id), 2) AS oral_last_pct,
  ROUND(100.0 * (COUNT(ol.hadm_id) - COUNT(o.hadm_id)) / COUNT(c.hadm_id), 2) AS oral_net_change
FROM cohort c
LEFT JOIN insulin_first i ON c.hadm_id = i.hadm_id
LEFT JOIN insulin_last il ON c.hadm_id = il.hadm_id
LEFT JOIN oral_first o ON c.hadm_id = o.hadm_id
LEFT JOIN oral_last ol ON c.hadm_id = ol.hadm_id;
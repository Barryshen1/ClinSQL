WITH surgical_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON a.hadm_id = pi.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.discharge_location IN ('HOME', 'SNF', 'REHAB', 'LTACH', 'DEATH')
),
categorized_discharge AS (
  SELECT
    CASE
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'FACILITY'
      WHEN discharge_location = 'DEATH' THEN 'DEATH'
    END AS discharge_category,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM surgical_admissions
)
SELECT
  discharge_category,
  COUNTIF(los >= 7) * 1.0 / COUNT(*) AS prop_los_ge7,
  COUNTIF(los >= 14) * 1.0 / COUNT(*) AS prop_los_ge14
FROM categorized_discharge
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;